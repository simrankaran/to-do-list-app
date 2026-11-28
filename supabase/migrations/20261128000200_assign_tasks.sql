-- Assign a task to a connected person.
--
-- The person a task is assigned to can see it and its files, and can mark it
-- started or done. They cannot change anything else, cannot delete it, and
-- still cannot see any of the owner's other tasks.
begin;

alter table public.tasks
  add column if not exists assignee_id uuid references auth.users (id) on delete set null;

create index if not exists tasks_assignee_idx
  on public.tasks (assignee_id) where assignee_id is not null;

-- Who may do what -------------------------------------------------------------

drop policy if exists "assigned tasks readable" on public.tasks;
create policy "assigned tasks readable" on public.tasks
  for select to authenticated
  using (assignee_id = (select auth.uid()));

drop policy if exists "assignee updates progress" on public.tasks;
create policy "assignee updates progress" on public.tasks
  for update to authenticated
  using (assignee_id = (select auth.uid()))
  with check (assignee_id = (select auth.uid()));

-- Enforces the rules on every write, whatever the app sends:
--   * the assignee can change only "done" and "in progress";
--   * a task can only be assigned to an accepted connection.
create or replace function public.tasks_assign_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  keep_done boolean;
  keep_progress boolean;
begin
  -- Changes made by the database itself (see friendships_unassign).
  if uid is null or pg_trigger_depth() > 1 then
    return new;
  end if;

  if tg_op = 'UPDATE' and uid is distinct from old.user_id then
    keep_done := new.done;
    keep_progress := new.in_progress;
    new := old;
    new.done := keep_done;
    new.in_progress := keep_progress;
    return new;
  end if;

  if new.assignee_id is not null
     and (tg_op = 'INSERT' or new.assignee_id is distinct from old.assignee_id) then
    if new.assignee_id = new.user_id then
      new.assignee_id := null;
    elsif not exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and ((f.requester_id = new.user_id and f.addressee_id = new.assignee_id)
          or (f.requester_id = new.assignee_id and f.addressee_id = new.user_id))
    ) then
      raise exception 'You can only assign tasks to people you are connected with.';
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function public.tasks_assign_guard() from public, anon, authenticated;

-- Named to run before tasks_touch, which then stamps completed_at.
drop trigger if exists tasks_assign_guard on public.tasks;
create trigger tasks_assign_guard
before insert or update on public.tasks
for each row execute function public.tasks_assign_guard();

-- Removing a connection takes back every task shared across it.
create or replace function public.friendships_unassign()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.tasks
     set assignee_id = null
   where (user_id = old.requester_id and assignee_id = old.addressee_id)
      or (user_id = old.addressee_id and assignee_id = old.requester_id);
  return old;
end;
$$;

revoke execute on function public.friendships_unassign() from public, anon, authenticated;

drop trigger if exists friendships_unassign on public.friendships;
create trigger friendships_unassign
after delete on public.friendships
for each row execute function public.friendships_unassign();

-- Files on an assigned task ---------------------------------------------------

drop policy if exists "assignee reads attachments" on public.task_attachments;
create policy "assignee reads attachments" on public.task_attachments
  for select to authenticated
  using (exists (
    select 1 from public.tasks t
    where t.id = task_attachments.task_id
      and t.assignee_id = (select auth.uid())
  ));

-- Files live at attachments/<owner id>/<task id>/<file>.
drop policy if exists "assignee reads attachment files" on storage.objects;
create policy "assignee reads attachment files" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'attachments'
    and exists (
      select 1 from public.tasks t
      where t.assignee_id = (select auth.uid())
        and t.user_id::text = (storage.foldername(objects.name))[1]
        and t.id::text = (storage.foldername(objects.name))[2]
    )
  );

-- Videos and presentations, up to 50 MB.
update storage.buckets
   set file_size_limit = 50 * 1024 * 1024,
       allowed_mime_types = array[
         'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic',
         'application/pdf',
         'video/mp4', 'video/quicktime', 'video/webm', 'video/3gpp',
         'application/vnd.ms-powerpoint',
         'application/vnd.openxmlformats-officedocument.presentationml.presentation'
       ]
 where id = 'attachments';

-- Live updates when a task is assigned or its progress changes.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'tasks'
  ) then
    alter publication supabase_realtime add table public.tasks;
  end if;
end;
$$;

commit;

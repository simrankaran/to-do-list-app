-- Photos and PDFs attached to tasks.
-- Files live privately at attachments/<user id>/<task id>/<file>;
-- the table records which file belongs to which task.

create table public.task_attachments (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  task_id    uuid not null,
  name       text not null check (char_length(name) between 1 and 200),
  path       text not null unique,
  mime_type  text not null,
  size_bytes integer not null check (size_bytes >= 0),
  created_at timestamptz not null default now(),
  foreign key (task_id, user_id) references public.tasks (id, user_id) on delete cascade
);

create index task_attachments_task_idx on public.task_attachments (task_id, user_id);
create index task_attachments_user_idx on public.task_attachments (user_id);

alter table public.task_attachments enable row level security;

create policy "own attachments" on public.task_attachments
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Private bucket: files are only reachable through short-lived signed URLs.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'attachments',
  'attachments',
  false,
  10 * 1024 * 1024,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic', 'application/pdf']
)
on conflict (id) do nothing;

create policy "attachment owner can read" on storage.objects
  for select to authenticated
  using (bucket_id = 'attachments' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "attachment owner can upload" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'attachments' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "attachment owner can delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'attachments' and (storage.foldername(name))[1] = (select auth.uid())::text);

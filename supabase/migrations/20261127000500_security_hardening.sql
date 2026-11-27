-- Security hardening after a review of the people/chat feature.
-- Safe to run more than once: it runs as one transaction and skips
-- anything that already exists.

begin;

-- 1. Internal trigger functions must not be callable through the API.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.tasks_touch() from public, anon, authenticated;

-- 2. Signed-out visitors never touch these tables, and nobody needs
--    TRUNCATE (which ignores row level security), REFERENCES or TRIGGER.
revoke all on all tables in schema public from anon;
revoke truncate, references, trigger on all tables in schema public from authenticated;
revoke all on public.assistant_usage from authenticated;

-- 3. Profiles: the person who SENT a request can't see the other person's
--    profile until it is accepted. The person who RECEIVED it can see who
--    is asking.
drop policy if exists "read own and connected profiles" on public.profiles;
drop policy if exists "read own, friends' and requesters' profiles" on public.profiles;

create policy "read own, friends' and requesters' profiles" on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or exists (
      select 1 from public.friendships f
      where (
        f.status = 'accepted'
        and ((f.requester_id = (select auth.uid()) and f.addressee_id = profiles.id)
          or (f.addressee_id = (select auth.uid()) and f.requester_id = profiles.id))
      ) or (
        f.status = 'pending'
        and f.addressee_id = (select auth.uid())
        and f.requester_id = profiles.id
      )
    )
  );

-- Only the editable fields can be written; "joined" can't be faked.
revoke insert, update, delete on public.profiles from authenticated;
grant insert (id, display_name, bio, avatar_url) on public.profiles to authenticated;
grant update (id, display_name, bio, avatar_url) on public.profiles to authenticated;

-- A profile photo must be the owner's own file in this project's avatars
-- bucket, so it can't be a link to someone else's server. Clear any photo
-- link that doesn't fit first, so the rule can be added.
update public.profiles
set avatar_url = null
where avatar_url is not null
  and avatar_url not like
    'https://cfrjrvkkkrkxggsticwe.supabase.co/storage/v1/object/public/avatars/' || id::text || '/%';

alter table public.profiles drop constraint if exists profiles_avatar_is_own_file;
alter table public.profiles add constraint profiles_avatar_is_own_file check (
  avatar_url is null
  or avatar_url like
    'https://cfrjrvkkkrkxggsticwe.supabase.co/storage/v1/object/public/avatars/' || id::text || '/%'
);

-- New accounts start without a photo (sign-up metadata is user-supplied).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    insert into public.profiles (id, display_name)
    values (new.id, left(split_part(coalesce(new.email, ''), '@', 1), 50))
    on conflict (id) do nothing;
  exception when others then
    -- Never block a sign-up because of the profile row.
    null;
  end;
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- 4. Messages: a sender supplies only the recipient and the text. The
--    sender, time and read mark are set by the database.
revoke insert, delete on public.messages from authenticated;
grant insert (recipient_id, body) on public.messages to authenticated;

-- 5. Friend requests: remember the email that was typed (shown to the sender
--    while waiting, since the profile is now hidden), and cap how many
--    requests one account can send per day so emails can't be probed in bulk.
alter table public.friendships add column if not exists requested_email text;

create table if not exists public.friend_request_log (
  user_id    uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists friend_request_log_user_idx
  on public.friend_request_log (user_id, created_at);
alter table public.friend_request_log enable row level security;
revoke all on public.friend_request_log from anon, authenticated;

create or replace function public.send_friend_request(target_email text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  cleaned text := lower(trim(coalesce(target_email, '')));
  target uuid;
  existing public.friendships;
begin
  if me is null then
    raise exception 'Not signed in';
  end if;
  if cleaned = '' or char_length(cleaned) > 320 then
    return;
  end if;

  -- Every attempt counts, whether or not the email has an account.
  if (select count(*) from public.friend_request_log l
      where l.user_id = me and l.created_at > now() - interval '24 hours') >= 15 then
    raise exception 'You have sent a lot of requests today. Try again tomorrow.';
  end if;
  insert into public.friend_request_log (user_id) values (me);

  select u.id into target
  from auth.users u
  where lower(u.email) = cleaned
  limit 1;

  if target is null or target = me then
    return;
  end if;

  select f.* into existing
  from public.friendships f
  where least(f.requester_id, f.addressee_id) = least(me, target)
    and greatest(f.requester_id, f.addressee_id) = greatest(me, target);

  if found then
    -- They had already asked me: asking back accepts it.
    if existing.status = 'pending' and existing.addressee_id = me then
      update public.friendships set status = 'accepted' where id = existing.id;
    end if;
    return;
  end if;

  if (select count(*) from public.friendships f
      where f.requester_id = me and f.status = 'pending') >= 20 then
    raise exception 'You have too many requests waiting. Try again later.';
  end if;

  insert into public.friendships (requester_id, addressee_id, requested_email)
  values (me, target, cleaned);
end;
$$;

revoke execute on function public.send_friend_request(text) from public, anon;
grant execute on function public.send_friend_request(text) to authenticated;

-- 6. An attachment record can only point inside its owner's storage folder.
alter table public.task_attachments drop constraint if exists task_attachments_own_path;
alter table public.task_attachments add constraint task_attachments_own_path
  check (path like user_id::text || '/%');

commit;

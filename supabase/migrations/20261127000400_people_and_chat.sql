-- People and chat: public-facing profiles, friend connections and direct
-- messages. Tasks stay private: nothing here grants access to them.

-- Profiles -------------------------------------------------------------------

create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 50),
  bio          text not null default '' check (char_length(bio) <= 200),
  avatar_url   text,
  created_at   timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Connections ----------------------------------------------------------------

create table public.friendships (
  id           uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users (id) on delete cascade,
  addressee_id uuid not null references auth.users (id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at   timestamptz not null default now(),
  check (requester_id <> addressee_id)
);

-- One connection per pair of people, whoever asked first.
create unique index friendships_pair_idx on public.friendships
  (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index friendships_requester_idx on public.friendships (requester_id);
create index friendships_addressee_idx on public.friendships (addressee_id);

alter table public.friendships enable row level security;

create policy "see own connections" on public.friendships
  for select to authenticated
  using ((select auth.uid()) in (requester_id, addressee_id));

-- Only the person who was asked can accept, and only accept.
create policy "accept requests sent to me" on public.friendships
  for update to authenticated
  using (addressee_id = (select auth.uid()) and status = 'pending')
  with check (addressee_id = (select auth.uid()) and status = 'accepted');

-- Either person can decline, cancel or remove the connection.
create policy "remove own connections" on public.friendships
  for delete to authenticated
  using ((select auth.uid()) in (requester_id, addressee_id));

-- Requests are created only through send_friend_request(), and only the
-- status column may be changed directly.
revoke insert, update on public.friendships from anon, authenticated;
grant update (status) on public.friendships to authenticated;

-- You can read your own profile and the profile of anyone you have a
-- connection with (including pending requests, so you can see who is asking).
create policy "read own and connected profiles" on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or exists (
      select 1 from public.friendships f
      where (f.requester_id = (select auth.uid()) and f.addressee_id = profiles.id)
         or (f.addressee_id = (select auth.uid()) and f.requester_id = profiles.id)
    )
  );

create policy "create own profile" on public.profiles
  for insert to authenticated
  with check (id = (select auth.uid()));

create policy "edit own profile" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- Sends a request to the account with this email. It never says whether the
-- email belongs to an account, so it can't be used to look people up.
create function public.send_friend_request(target_email text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  target uuid;
  existing public.friendships;
begin
  if me is null then
    raise exception 'Not signed in';
  end if;

  select u.id into target
  from auth.users u
  where lower(u.email) = lower(trim(target_email))
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

  insert into public.friendships (requester_id, addressee_id) values (me, target);
end;
$$;

revoke execute on function public.send_friend_request(text) from public, anon;
grant execute on function public.send_friend_request(text) to authenticated;

-- Messages -------------------------------------------------------------------

create table public.messages (
  id           uuid primary key default gen_random_uuid(),
  sender_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  recipient_id uuid not null references auth.users (id) on delete cascade,
  body         text not null check (char_length(body) between 1 and 2000),
  created_at   timestamptz not null default now(),
  read_at      timestamptz
);

create index messages_sender_idx on public.messages (sender_id, recipient_id, created_at);
create index messages_recipient_idx on public.messages (recipient_id, sender_id, created_at);

alter table public.messages enable row level security;

create policy "read own conversations" on public.messages
  for select to authenticated
  using ((select auth.uid()) in (sender_id, recipient_id));

-- You can only message people who accepted a connection with you.
create policy "message accepted connections" on public.messages
  for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and ((f.requester_id = sender_id and f.addressee_id = recipient_id)
          or (f.requester_id = recipient_id and f.addressee_id = sender_id))
    )
  );

-- The recipient can mark a message as read, and nothing else.
create policy "mark received messages read" on public.messages
  for update to authenticated
  using (recipient_id = (select auth.uid()))
  with check (recipient_id = (select auth.uid()));

revoke update on public.messages from anon, authenticated;
grant update (read_at) on public.messages to authenticated;

-- New accounts get a profile automatically ------------------------------------

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    insert into public.profiles (id, display_name, avatar_url)
    values (
      new.id,
      left(split_part(coalesce(new.email, ''), '@', 1), 50),
      new.raw_user_meta_data ->> 'avatar_url'
    )
    on conflict (id) do nothing;
  exception when others then
    -- Never block a sign-up because of the profile row.
    null;
  end;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- Profiles for the accounts that already exist.
insert into public.profiles (id, display_name, avatar_url)
select u.id,
       left(split_part(coalesce(u.email, ''), '@', 1), 50),
       u.raw_user_meta_data ->> 'avatar_url'
from auth.users u
on conflict (id) do nothing;

-- Live updates for new messages and requests.
alter publication supabase_realtime add table public.messages, public.friendships;

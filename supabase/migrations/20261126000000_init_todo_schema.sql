-- To-do app schema: projects, tags, tasks (with subtasks), task_tags.
-- Every row is owned by a user; RLS limits each user to their own rows.
-- Composite (id, user_id) foreign keys stop a row from pointing at another user's data.

create table public.projects (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 100),
  color      integer not null default 4284955319, -- ARGB, Colors.deepPurple
  created_at timestamptz not null default now(),
  unique (id, user_id)
);

create table public.tags (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 50),
  color      integer not null default 4280391411, -- ARGB, Colors.blue
  created_at timestamptz not null default now(),
  unique (id, user_id),
  unique (user_id, name)
);

create table public.tasks (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  project_id   uuid,
  parent_id    uuid,
  title        text not null check (char_length(title) between 1 and 500),
  notes        text not null default '',
  priority     smallint not null default 0 check (priority between 0 and 3), -- 0 none, 1 low, 2 medium, 3 high
  due_at       timestamptz,
  done         boolean not null default false,
  completed_at timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (id, user_id),
  foreign key (project_id, user_id) references public.projects (id, user_id) on delete set null (project_id),
  foreign key (parent_id, user_id)  references public.tasks (id, user_id)    on delete cascade,
  check (parent_id is null or parent_id <> id)
);

create table public.task_tags (
  task_id uuid not null,
  tag_id  uuid not null,
  user_id uuid not null default auth.uid(),
  primary key (task_id, tag_id),
  foreign key (task_id, user_id) references public.tasks (id, user_id) on delete cascade,
  foreign key (tag_id, user_id)  references public.tags (id, user_id)  on delete cascade
);

create index tasks_user_id_idx    on public.tasks (user_id);
create index tasks_project_id_idx on public.tasks (project_id, user_id);
create index tasks_parent_id_idx  on public.tasks (parent_id, user_id);
create index tasks_due_at_idx     on public.tasks (user_id, due_at) where not done;
create index projects_user_id_idx on public.projects (user_id);
create index task_tags_tag_idx    on public.task_tags (tag_id, user_id);
create index task_tags_user_idx   on public.task_tags (user_id);
create index task_tags_task_idx   on public.task_tags (task_id, user_id);

-- Keep updated_at and completed_at in sync.
create function public.tasks_touch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  if new.done and (tg_op = 'INSERT' or not old.done) then
    new.completed_at := now();
  elsif not new.done then
    new.completed_at := null;
  end if;
  return new;
end;
$$;

create trigger tasks_touch
before insert or update on public.tasks
for each row execute function public.tasks_touch();

-- Row level security: each user sees and changes only their own rows.
alter table public.projects  enable row level security;
alter table public.tags      enable row level security;
alter table public.tasks     enable row level security;
alter table public.task_tags enable row level security;

create policy "own projects" on public.projects
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "own tags" on public.tags
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "own tasks" on public.tasks
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "own task_tags" on public.task_tags
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

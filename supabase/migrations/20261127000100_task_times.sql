-- Fixed start/end times for a task, and whether to notify at both.
alter table public.tasks
  add column starts_at timestamptz,
  add column ends_at   timestamptz,
  add column remind    boolean not null default true,
  add constraint tasks_time_range_check
    check (ends_at is null or (starts_at is not null and ends_at > starts_at));

create index tasks_starts_at_idx on public.tasks (user_id, starts_at) where starts_at is not null;

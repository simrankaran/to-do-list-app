-- Board view: a task can be marked as being worked on ("Doing").
alter table public.tasks
  add column if not exists in_progress boolean not null default false;

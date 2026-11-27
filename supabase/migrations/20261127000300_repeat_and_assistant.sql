-- Repeating tasks: how a task repeats, and for 'days' which weekdays
-- (bit 0 = Monday ... bit 6 = Sunday).
alter table public.tasks
  add column repeat_rule text not null default 'none'
    check (repeat_rule in ('none', 'daily', 'weekly', 'monthly', 'days')),
  add column repeat_days smallint not null default 0 check (repeat_days between 0 and 127);

-- Per-user daily message count for the AI assistant, so one account can't
-- run up the bill. Only the assistant edge function (service role) touches
-- this table: RLS is on and there are no policies.
create table public.assistant_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day     date not null,
  count   integer not null default 0,
  primary key (user_id, day)
);

alter table public.assistant_usage enable row level security;

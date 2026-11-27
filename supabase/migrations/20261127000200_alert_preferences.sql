-- Per-task notification preferences: custom messages, an early heads-up,
-- and how the alert sounds.
alter table public.tasks
  add column start_message text not null default '' check (char_length(start_message) <= 200),
  add column end_message   text not null default '' check (char_length(end_message) <= 200),
  add column early_minutes smallint not null default 0 check (early_minutes in (0, 5, 10, 15, 30, 60)),
  add column alert_style   text not null default 'sound' check (alert_style in ('sound', 'vibrate', 'silent')),
  add column alert_sound   text not null default 'default' check (alert_sound in ('default', 'chime', 'bell', 'beep', 'digital'));

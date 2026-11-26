-- ARGB colors (e.g. 0xFF673AB7 = 4284955319) exceed the signed 32-bit integer range.
alter table public.projects alter column color type bigint;
alter table public.tags     alter column color type bigint;

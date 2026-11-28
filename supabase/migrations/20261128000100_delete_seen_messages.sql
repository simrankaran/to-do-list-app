-- One-time chat: a message is deleted for good as soon as the person it was
-- sent to has seen it, so conversations never pile up in the database.
begin;

-- Only the recipient can delete a message, and only one sent to them.
drop policy if exists "delete seen messages" on public.messages;
create policy "delete seen messages" on public.messages
  for delete to authenticated
  using (recipient_id = (select auth.uid()));

grant delete on public.messages to authenticated;

-- Messages that were already read under the old behaviour go too.
delete from public.messages where read_at is not null;

commit;

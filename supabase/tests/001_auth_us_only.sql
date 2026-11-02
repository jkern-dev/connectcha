-- Scenario 10: a non-US number cannot sign up. The GoTrue before_user_created
-- hook calls this function with the would-be user; an error payload refuses it.
begin;
select plan(6);

select is(
  public.before_user_created_hook('{"user":{"phone":"15550000001"}}'::jsonb),
  '{}'::jsonb,
  'a US number (+1 and ten digits) is allowed'
);

select isnt(
  public.before_user_created_hook('{"user":{"phone":"447700900123"}}'::jsonb) -> 'error',
  null,
  'a UK number is refused'
);

select isnt(
  public.before_user_created_hook('{"user":{"phone":"34612345678"}}'::jsonb) -> 'error',
  null,
  'a Spanish number is refused'
);

select isnt(
  public.before_user_created_hook('{"user":{"phone":"5550000001"}}'::jsonb) -> 'error',
  null,
  'a ten-digit number without the country code is refused (the app always sends +1)'
);

select is(
  public.before_user_created_hook('{"user":{"phone":"447700900123"}}'::jsonb) -> 'error' ->> 'message',
  'Only US phone numbers can sign up right now.',
  'the refusal carries a plain-language message'
);

select tests.authenticate_as_anon();
select throws_ok(
  $$ select public.before_user_created_hook('{}'::jsonb) $$,
  '42501',
  null,
  'clients cannot call the auth hook'
);

select * from finish();
rollback;

# Graduation and handoff (#34)

`lib/project/graduation.aura` decides when a green-field repository has
become self-bootstrapping and the conductor must step back.

## Conditions

A run counts only when all of these hold:

- `conductor_absent`
- `evidence_pr`
- `canary`
- `sentinel_untouched`
- `redlines_ok`
- `budget_active`

`graduation:policy` requires `rounds` (default 3, a target until the first
project measurement) and `takeover_ms` (default one hour). The policy is
configurable at `graduation:new`; the values are not presented as
measured results.

`graduation:handoff` additionally requires:

- a sentinel fingerprint;
- a merge evidence hash that passes `redline:merge` (protected branch,
  required checks, no force/admin/direct push).

It produces a `graduation-report` with seed version, locked Aura commit
and `aura-ci` digest from `baseline/aura-baseline.json`, sentinel
fingerprint, round ids, PR numbers, risks, the red-line policy and
explicit `tag = #f`, `release = #f`, `daily_dispatch = #f`.

## After graduation

- `graduation:dispatch` refuses a daily `feature`/`post-task` request
  with `daily-dispatch-refused` and points at escalation.
- `inception`, `major-upgrade` and `stuck` route to escalation.
- `graduation:escalate` opens one bounded takeover with an expiry.
- While the takeover is active, daily dispatch routes to `takeover`.
- `graduation:tick` expires it and returns to `graduated`; the takeover
  does not silently become long-term command.

## Evidence

`tests/graduation_test.aura` covers:

- two good rounds are not enough; a rejected round is audited;
- a sentinel-touching round cannot make a one-round policy graduate;
- handoff writes no tag/release and marks daily dispatch off;
- daily dispatch is refused, inception is allowed;
- takeover dispatch works, expires at the boundary, and returns to
  graduated;
- a force merge is refused by the red-line gate.

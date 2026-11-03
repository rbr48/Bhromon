# Call quality under network impairment

This is the written procedure for roadmap item O-04: calls tested with scripted
packet loss, latency and bandwidth limits. It says how to run the tests. The
results section is filled in when the device lab (O-03) runs them.

## What is measured

Each call is measured by the call summary the app writes (`CallSummary`, S-06).
The keys to read are:

- `setup_ms`: time from starting the call to the first connected state.
- `connected_s`: seconds connected.
- `path`: the connection type the call settled on (direct, relay, and so on).
- `reconnects`: how many times the link was rebuilt.
- `loss_peak`: the highest packet loss seen in one poll interval (`PacketLossMeter`).
- `end_reason`: why the call ended.

The summaries reach Crashlytics as custom keys. The tester also rates what they
hear and see, from 1 (unusable) to 5 (clear), on each call.

## Equipment

- Two Android phones, one of them a Samsung or a Xiaomi.
- A Linux host with two network interfaces. It bridges the phones to the
  internet and applies the impairment. A VM or a container works.
- The host needs `iproute2` (for `tc`) and root access.
- A call partner who is not on the impaired link, so only one direction is
  impaired at a time.

## Impairment profiles

Apply each profile to the phone's link only. Do not apply it to the host's
management interface.

| Profile | Command (interface `IFACE`) |
|---|---|
| Loss 2% | `tc qdisc replace dev IFACE root netem loss 2%` |
| Loss 5% | `tc qdisc replace dev IFACE root netem loss 5%` |
| Loss 10% | `tc qdisc replace dev IFACE root netem loss 10%` |
| Latency 150 ms, jitter 30 ms | `tc qdisc replace dev IFACE root netem delay 150ms 30ms` |
| Bandwidth 300 kbit/s | `tc qdisc replace dev IFACE root tbf rate 300kbit burst 8kbit latency 200ms` |

Remove the profile after each run:

```sh
tc qdisc del dev IFACE root
```

## Scenarios

Run every scenario on each profile, three times, and keep all results:

1. Voice call, 3 minutes, caller on the impaired phone.
2. Voice call, 3 minutes, callee on the impaired phone.
3. Video call, 3 minutes, caller on the impaired phone.
4. Accept on a locked phone (scenario C-01 in the test plan), with the profile applied
   before the call starts.

## Pass criteria (confirmed by the owner; revisit after the first device-lab run)

- The call connects on every run at 2% and 5% loss.
- At 10% loss, the call connects on at least two of three runs, and the
  connection is either direct or relay.
- `setup_ms` at 2% loss has a median under 5 seconds.
- A voice call is rated 3 or more at 5% loss.
- Every run ends with a reason that matches what happened.

## Recording

Store each run in a row of this table, with the device models and the app
build:

| Date | Build | Phone A | Phone B | Profile | Scenario | Run | setup_ms | connected_s | path | reconnects | loss_peak | rating | end_reason | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|

## Results

Not yet run. The device lab (O-03) runs these, with at least four Android
devices, one of them a Xiaomi and one a Samsung.

## Clean-up

After each session, remove every profile with `tc qdisc del` and confirm with
`tc qdisc show dev IFACE` that only the default qdisc remains.

[中文](README.zh-CN.md)

# K3 Pico continuous fan policy

This repository is a companion to the benchmark workspace. It keeps the
SpacemiT K3 Pico fan running continuously by holding the `pwm-fan` cooling
level at or above a configured floor. It carries no benchmark result and no
report.

## Why a service is needed

The board exposes the fan twice:

- the `pwmfan` hwmon device with `pwm1` and `pwm1_enable`; and
- the `pwm-fan` thermal cooling device with `cur_state` in `0..max_state`.

The cooling device is bound to the `thermal_cluster0` zone, whose only
registered policy is `step_wise`. The kernel therefore keeps moving the level
with temperature and stops the fan at level `0` once the board is cool.
`user_space` is not available on this board, so the level cannot be pinned from
the kernel side and the guard re-asserts the floor from userspace.

Measured level to duty mapping on the K3 Pico ITX:

| level | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|---|
| `pwm1` | 0 | 30 | 60 | 90 | 120 | 149 | 170 | 191 | 213 |

The default policy pins the fan at level `8`, so the fan never stops.

## Install, status, and removal

```sh
hardware/k3-fan-control/scripts/build.sh
hardware/k3-fan-control/scripts/run.sh
hardware/k3-fan-control/scripts/run.sh --status
hardware/k3-fan-control/scripts/run.sh --uninstall
```

`scripts/run.sh` reads the board connection from the workspace record
`<workspace>/.ssh-k3`, which must be mode `0600` and is never printed. Delivery
is host to device: the host pushes the payload and enables the service on the
board. `sshpass`, `ssh`, and `scp` are required on the host.

## Files installed on the board

- `/usr/local/lib/k3-fan-control/k3-fan-guard`, the guard itself
- `/etc/k3-fan-control.conf`, the level floor and the re-assert interval
- `/etc/systemd/system/k3-fan-continuous.service`, enabled at boot
- `/usr/local/share/doc/k3-fan-control/README.md`

## Configuration

- `FAN_MIN_STATE` is the lowest level the fan may drop to. `0` stops the fan,
  `8` is the maximum, and the default `8` buys the strongest continuous cooling.
- `FAN_REASSERT_SECONDS` is the re-assert interval. The default `1` is short
  enough to correct a kernel level change almost immediately.

Edit `/etc/k3-fan-control.conf` on the board, then run
`systemctl reload k3-fan-continuous.service` to apply the new floor.

## Verification

- `k3-fan-guard --status` prints the cooling device, level, floor, `pwm1`,
  every thermal zone policy and temperature, and the EC fan tachometer when the
  board exposes it.
- The unit uses `Restart=always`, so a guard failure is recovered within a
  second.

## Limitations

- The guard enforces a floor and never a ceiling: a hot board may still be given
  a higher level by the kernel.
- `scripts/build.sh` validates syntax, configuration, and the unit only; fan
  behaviour can only be verified on the board.

## Workspace integration

This repository lives at `hardware/k3-fan-control` inside the workspace and
carries its own Git history. It is not listed in the workspace manifest yet,
because the manifest resolves `k3-fan-control.git` from the shared remote and
the first push still needs human approval. Once the remote repository exists,
add this entry to `default.xml`:

```xml
<project name="k3-fan-control.git" path="hardware/k3-fan-control" />
```

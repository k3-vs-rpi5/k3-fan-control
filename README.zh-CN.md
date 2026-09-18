[English](README.md)

# K3 Pico 持续风扇策略

本仓库是评测工作区的配套组件，通过把 `pwm-fan` 冷却级别保持在配置的下限之上，
让 SpacemiT K3 Pico 的风扇持续运转。它不保存任何评测结果，也不保存报告。

## 为什么需要常驻服务

板子上风扇有两处接口：

- `pwmfan` hwmon 设备，提供 `pwm1` 与 `pwm1_enable`；
- `pwm-fan` 热冷却设备，提供 `0..max_state` 范围内的 `cur_state`。

该冷却设备绑定在 `thermal_cluster0` 温区上，而该温区唯一注册的策略是
`step_wise`。因此内核会随温度不断调整级别，板子变凉后会把风扇停到级别 `0`。
本板不支持 `user_space` 策略，无法从内核侧固定级别，所以由守护进程在用户态
持续重新施加下限。

K3 Pico ITX 上实测的级别与占空比映射：

| 级别 | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|---|
| `pwm1` | 0 | 30 | 60 | 90 | 120 | 149 | 170 | 191 | 213 |

默认策略把风扇固定在级别 `8`，因此风扇不会停止。

## 安装、查看与卸载

```sh
hardware/k3-fan-control/scripts/build.sh
hardware/k3-fan-control/scripts/run.sh
hardware/k3-fan-control/scripts/run.sh --status
hardware/k3-fan-control/scripts/run.sh --uninstall
```

`scripts/run.sh` 从工作区记录 `<workspace>/.ssh-k3` 读取板卡连接信息，该文件
权限必须为 `0600`，且绝不打印其内容。交付方向是主机到设备：由主机推送负载，
并在板卡上启用服务。主机需要 `sshpass`、`ssh` 与 `scp`。

板卡地址变化时无需修改该记录：在调用时导出 `K3_BOARD_HOST=<address>` 即可，例如
`K3_BOARD_HOST=192.168.100.215 scripts/run.sh`。

## 板卡上安装的文件

- `/usr/local/lib/k3-fan-control/k3-fan-guard`，守护脚本本身
- `/etc/k3-fan-control.conf`，级别下限与重新施加间隔
- `/etc/systemd/system/k3-fan-continuous.service`，开机自启
- `/usr/local/share/doc/k3-fan-control/README.md`

## 配置

- `FAN_MIN_STATE` 是风扇允许降到的最低级别。`0` 表示停转，`8` 为最大值，默认
  `8` 可获得最强且持续的散热。
- `FAN_REASSERT_SECONDS` 是重新施加的间隔。默认 `1` 足以在内核改动级别后几乎
  立即纠正。

在板卡上编辑 `/etc/k3-fan-control.conf` 即可：守护进程每个间隔开始时都会重新
读取该文件，因此新的下限会在一秒内生效，而执行
`systemctl reload k3-fan-continuous.service` 可以立即生效，不必等下一个周期。

## 验证

- `k3-fan-guard --status` 会打印冷却设备、当前级别、下限、`pwm1`、每个温区的
  策略与温度，并尽力附带本板暴露的 `hwmon7/fan1_input` EC 风扇转速。
- 服务使用 `Restart=always`，守护进程异常会在一秒内恢复。
- `tests/guard-test.sh` 无需板卡即可校验下限逻辑：它在私有 mount namespace 中
  构造伪造的 sysfs 树，确认守护进程会抬升低于下限的级别、采用配置的下限，并在
  运行中接收到编辑后的下限。

## 限制

- 守护进程只保证下限，不设上限：板子变热时内核仍可给出更高的级别。
- `--uninstall` 会停用并禁用服务、删除守护进程与 unit，但保留
  `/etc/k3-fan-control.conf` 与已安装文档，因此重新安装会沿用编辑过的下限，
  而不会静默复位。
- `scripts/build.sh` 只校验语法、配置和 unit；风扇行为只能在板卡上验证。

## 工作区集成

本仓库位于工作区的 `hardware/k3-fan-control`，自带 Git 历史。它目前还没有登记
到工作区 manifest 中，因为 manifest 会从共享远端解析 `k3-fan-control.git`，而
首次 push 仍需人工批准。远端仓库就绪后，把下面这行加入 `default.xml`：

```xml
<project name="k3-fan-control.git" path="hardware/k3-fan-control" />
```

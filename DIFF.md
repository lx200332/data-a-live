# popsicle 适配改动记录（相对上游 data-a-live `db88a20`）

上游目标机 = **Xiaomi 17 Pro（pandora / SM8850）**；本机 = **Xiaomi 17 Pro Max（popsicle / 2509FPN0BC / SM8850 canoe）**。
两机同 SoC、同 PMIC、同触摸控制器，**唯一实质差异是主屏分辨率**。

一共 **26 个文件、90 增 90 删**，全部在 `C:\dsh-对话\data-a-live-popsicle`（分支 `popsicle-adapt`），上游 `data-a-live` 保持 pristine。

三种用法（`adapt_popsicle.py` 是 `popsicle-adapt.patch` 的应用器，幂等、可逆）：

```
python3 adapt_popsicle.py --check     # 校验能否干净应用
python3 adapt_popsicle.py             # 应用
python3 adapt_popsicle.py --revert    # 还原到上游原样
```

已验证：`--revert` 后再 `apply` 能精确回到同一状态；`popsicle-adapt.patch` 在 pristine 上游上 `git apply --check` 通过。

---

## 一、几何：1220×2656 / stride 4880 → 1200×2608 / stride 4800

本机证据：`display-dmesg-notes.md:16`（hactive=1200, vactive=2608）、`boots/INDEX.md:4`（ADT 几何 1200x2608/4800）、`drm-card0-DSI-1/modes.txt` 的 `1200x2608x120cmd`、`popsicle_overlay.dts` 面板节点 `qcom,mdss-dsi-panel-width = <0x5a0>`（1200）/ `panel-height = <0xc80>`（2608）。

| 文件 | 改了什么 |
|---|---|
| `tools/mkadt_pandora.py:56` | `FB_W, FB_H, FB_STRIDE` → `1200, 2608, 1200 * 4` |
| `bootmgr/menu.c:29-31` | `FB_W/FB_H/FB_STRIDE` 三个 `#define` |
| `shim/loader/loader.c:10,26-28` | 注释里的 `1220x2656, stride 4880` + 三个 `#define` |
| `shim/hello/hello.c:144` | `fb_w/fb_h/fb_stride` 赋值 |
| `tools/qemu_loader.py:11,16` | docstring + `FB_W/FB_H` |
| `wsl/pandora_dpu.c:291-292,323-325,655-656` | `SC_PANEL_W/SC_HALF_W/SC_PANEL_H`（1220/610/2656 → 1200/600/2608），注释里 `0-609`/`610-1219` → `0-599`/`600-1199`，混合器分界 `panel x 610` → `600` |
| `wsl/pandora_touch.c:1286,1300-1304,1408-1410,1477-1478` | 面板→呈现坐标的换算分母、居中偏移、IC 原始值→面板像素、THP 插值，共 9 处 |
| `xnu/patches/0217-pandora-scanout.patch:77-78,109-111,436-437` | 与 `pandora_dpu.c` 同源的 scanout 补丁 |
| `xnu/patches/0125-pandora-present-iphone-x-centered.patch:11,13` | 注释；居中黑边 `47px` 左右 / `110px` 上下 → **`37px` / `86px`**（`(1200-1125)/2`、`(2608-2436)/2`） |
| `xnu/patches/0126-pandora-sweetfb-fill-scaling.patch:23` | 注释；铺满比例 `x1.084/y1.090` → **`x1.067/y1.071`**（`1200/1125`、`2608/2436`） |
| `xnu/patches/0130-pandora-volup-tlmm-and-touch.patch:1207-1215` | 触摸首版（`0134` 的前身），4 处 |
| `xnu/patches/0134-pandora-touch-thp-fallback.patch:92,106-110,146-161,233-234` | 触摸重写版，`-`/`+` 两侧共 9 处 |
| `wsl/fix_0125.sh:19`、`wsl/fix_0126.sh:31` | 生成脚本里的同段注释 |
| `bootmgr/mkboot.py:26` | `SAVE_AREA` 注释里的 `4880 * 96` → `4800 * 96`（数值 `0x100000` 不变，`460800 < 0x100000` 仍安全） |
| `PLAN.md:173,204,242,470`、`docs/EXPERIENCE.md:9`、`FUXI_NOTES.md:32` | 中文文档里描述本机屏幕的地方 |

**为什么 `0130`、`0134`、`pandora_touch.c` 三处都要改**：它们是同一段触摸代码的三代（`0130` 首版 → `0134` 重写 → 上游当前 `pandora_touch.c`）。补丁序列逐条应用，中间态和最终态必须自洽，否则 `series` 会把旧几何带回内核。

---

## 二、背光上限：0x1554（5460）→ 0x1fff（8191）

本机证据：`kernel-驱动-进度-20261027.md:1690-1725`、`live-fdt.dts:39915` 的 `mi,max-brightness-normal = <0x1fff>`、`:39943` 的 `qcom,mdss-dsi-bl-max-level = <0x3fff>`（16383）。
`0x1554` 在 `live-fdt.dts` 里只出现 4 次，全属别的面板 —— 上游拿的是 pandora 那块屏的正常量程上限。

- `xnu/patches/0139-pandora-dsi-brightness.patch:12,22`
- `wsl/fix_0139.py:14,24`

不改的后果：CoreBrightness 拉到 100% 时 DCS 0x51 也只写到 5460，只有硬件满量程的 33%，屏幕永远上不到最亮。

---

## 三、WiFi PCI device id：0x1107（kiwi / WCN7850）→ 0x110e（peach）

本机证据：DTB `supported-ids = <0x110e>`、dmesg `cnss: Device id: 0x110e`；仓库已有记录 `wifi-facts.md:13,43`、`boots/INDEX.md:78-82`。

`xnu/patches/0099-fuxi-wlan.patch` 里 `0x110717cb` 共 **6 处**（1002、1181、1211、2097、2677、2969 行），全部改为 `0x110e17cb`；另把 480 行注释的 `KIWI (0x1107)` 改成 `PEACH (0x110e)`。

不改的后果：`wl_probe_id` 处直接 `return 3`，`FUXI WLAN` 日志恒 0 行。

---

## 四、逐一核对后确认**不需要改**的项

| 项 | 上游值 | 本机值 | 判定 |
|---|---|---|---|
| 触摸 IRQ / reset | `PT_IRQ 158` / `PT_RESET 66` | DT `irq GPIO 158`、`reset GPIO 66` | 一致 |
| 触摸 SPI 基址 | `PT_SE_PA 0x01a80000` | `qupv3_4 SE0 0x1a80000` | 一致 |
| 触摸 AVDD | `PT_AVDD 117` | 同 | 一致 |
| TLMM 基址 | `PT_TLMM_PA 0x0f100000` | 真基址 `0x0f100000`（DT 写 `0xf000000` 是未加偏移的原始值） | 一致 |
| 音量上 GPIO | `VOLUP_GPIO 0x0f165000`（TLMM + 0x1000×101） | DT `vol_up gpios = <0xffffffff 0x65 0x1>` → GPIO 101、active low | 一致 |
| splash / framebuffer | `0xfc800000` + `0x2b00000` | 同 | 一致 |
| GIC | `GICD 0x17000000` / `GICR 0x17080000` / stride `0x40000` | 同 | 一致 |
| UFS | `0x01d84000` + `0x3000` | `ufshc@1d84000` | 一致 |
| MDSS / SMMU | `0x09800000` / `0x15000000` | `mdss_mdp@9800000` / `apps-smmu@15000000` | 一致 |
| DSI0 | `0x09ac0000` | `mdss_dsi_ctrl0@9ac0000` | 一致 |
| IPCC | `qcom,ipcc@1106000` | `ipcc@1106000` | 一致 |
| SPMI / PMIC arb | `0x0c400000` / `0x0c403000` / `0x0c42a000` / `0x0c4c0000` | `arbiter@c400000` + `spmi@c426000`/`c437000` | 一致 |
| **GPU 中断** | `GIC_SPI 300` → INTID 332 | DT `kgsl-3d0 interrupts = <0 0x12c 4>` → SPI 300 | **一致**（原「待核」，已关闭） |
| **显示中断** | `GIC_SPI 83` → INTID 115 | DT `sde-kms interrupts = <0 0x53 4>` → SPI 83 | **一致**（原「待核」，已关闭） |
| **IPCC 中断** | `GIC_SPI 246` | DT `ipcc interrupts = <0 0xf6 4>` → SPI 246 | **一致**（原「待核」，已关闭） |
| **14 路热敏电阻** | `pt_chan[]` 的 sdam/slot/reg 全表 | `popsicle_overlay.dts` 14 个 `qcom,adc-tm-type` 通道，reg 与顺序**逐个吻合** | **完全一致**（原「待核」，已关闭） |
| **ADSP 共享内存** | `DSP_SHM 0xb0000000` + 1 MiB | 解析 DT 70 个 reserved-memory 区间，`0xb0000000` **不落在任何区间**；上游 XNU RAM 段 `0x8c0000000+0x140000000` 在 `0xa0000000` 就结束，根本不相邻 | **安全**（原「待核」，已关闭） |
| 背屏 | 572×904，FocalTech | 596×976，Goodix GT9615 | 代码里**没有背屏尺寸硬编码**，无需改 |
| 面板节点名 | `qcom,mdss_dsi_q200_42_02_0a_p20_prim_dsc_cmd` | `qcom,mdss_dsi_p2_42_0d_0b_mp_prim_dsc_cmd` | 代码从不按名字引用面板（只按 `sweet,display` compatible + ADT 几何走），无需改 |
| 机器配置名 `PANDORA` / `-DPANDORA=1` / `xiaomi,pandora` | — | — | **保留**。ADT 由我们自己生成，内核 patch 0110 的 `IONameMatch` 硬编码 `xiaomi,pandora`；改名要连带 0110 + ADT + 全部 `#if defined(PANDORA)`，收益为零 |
| canvas 1125×2436 | `mkadt_pandora.py:328-329` | 同 | **保留**，这是 iPhone X 逻辑画面，与实机面板无关 |
| UART/PMIC 侧 GPIO 表 `pt_gpio[]` | `0x00be/0x0189/0x018a/0x0190/0x0193/0x2799/0x2793` | 两机同 PMIC（pmk8850 + pmh0101 + pmih010x） | 一致 |

---

## 五、已知仍存在的上游内部矛盾（未改，仅记录）

`xnu/patches/0128-pandora-keys-spmi-v8-tlmm.patch:34` 写 `#define PK_TLMM_GPIO 0x0f065000u`，
而同一注释说「TLMM + 0x1000 * 101」应为 `0x0f165000`；`0130` 的 `-` 行删掉 `0x0f065000` 换成 `0x0f165000`（正确值），`bootmgr/menu.c:36` 也是 `0x0f165000`。

**结论**：`0128` 那个值是笔误（读 `0x0f065000` 会挂在总线上），但 `0130` 已经把它改对了，所以**不改 `0128`**——改了会让 `0130` 的 `-` 行匹配不上，补丁序列反而断掉。

---

## 六、下一步（需真机）

本轮只动代码，没上机。分支 `popsicle-adapt`，21 个文件 81 行增删，全在 `C:\dsh-对话\data-a-live-popsicle`，上游 `data-a-live` 保持 pristine（`db88a20`）。

上机前还要做的：
1. 用改过的 `tools/mkadt_pandora.py` 重新生成 ADT，确认 `FB_W=1200` 落到 ADT 里。
2. 把 `MEM_SIZE 0x140000000` 对齐进来 —— 我们自己的 `board.toml` 现在写 `owned_memory_size = "0x130000000"`（`UniXNU-popsicle/README.md:303` 明确说「inherited from sheng」），比上游小 256 MiB；`全量审查-20261025.md:340` 已验 `0x140000000` 段内合法、GPU 池不越界。
3. `mkboot.py` 生成 `boot_b` 时用新的 `SAVE_AREA` 注释值核对一遍 `save_off + BAND_BYTES <= declared`。
4. 真机跑一次，看屏幕是否铺满、触摸定位是否对得上、背光能不能拉到 100%。

---

## 七、机型标识（不影响运行，只影响日志与文档可读性）

| 文件 | 改动 |
|---|---|
| `README.md:5` | `Xiaomi 17 Pro (pandora, SM8850)` → `Xiaomi 17 Pro Max (popsicle, SM8850)` |
| `tools/mkadt_pandora.py:2,5` | docstring 同上 + `the 17 Pro's live FDT` → `the 17 Pro Max's live FDT` |
| `shim/hello/hello.c:2` | 头注释机型 |
| `shim/loader/loader.c:2` | 头注释机型 |
| `wsl/pandora_config.sh:8` | 注释机型 |
| `wsl/fix_0108.sh:17`、`fix_0111.sh:11`、`fix_0132.sh:11` | 注释里的 `17 Pro` → `17 Pro Max` |

**注意**：`xiaomi,pandora` 这个 compatible 字符串**故意没改**——内核 patch 0110 的 `IONameMatch = 'xiaomi,pandora'` 硬编码它，而 ADT 由我们自己生成。改这个串要连 0110 + ADT + 全部 `#if defined(PANDORA)` 一起动，收益为零风险很大。

---

## 八、验证记录

```
$ python3 adapt_popsicle.py --check
待应用：26 个文件 90 增 90 删（基线 db88a20）
$ python3 adapt_popsicle.py
已应用 26 个文件 90 增 90 删（基线 db88a20）
$ python3 adapt_popsicle.py          # 幂等复跑
已应用（26 个文件有改动，可用 --revert 还原）
$ python3 adapt_popsicle.py --revert
已还原 26 个文件到上游原样（db88a20）

$ cd ../data-a-live && git apply --check ../data-a-live-popsicle/popsicle-adapt.patch
（通过，上游 pristine db88a20 未被触碰）
```

残留扫描：`1220 / 2656 / 4880` 只出现在 `adapt_popsicle.py`、`popsicle-adapt.patch`、`DIFF.md`（记录用）、`device/DT_FINDINGS.md`（pandora 原机史料）、`docs/GPU_PLAN.md:153`（`msm_gem.c:1211-1220` 是源码行号）、`0170-pandora-gpu-gx-vote-first.patch:24`（hunk 头 `@@ -1220,22`）。**代码里已无一处旧几何。**

---

## 九、顺手补上的上游缺件：`tools/adt.py`

`tools/mkadt_pandora.py:26` 写着 `import adt`，但**上游仓库里没有 `tools/adt.py`**（`git ls-files | grep adt` 只有 `mkadt_pandora.py`，`.gitignore` 也没屏蔽它，历史上从未提交过）。意味着**上游原样 checkout 后，ADT 生成器根本跑不起来**：

```
$ git checkout db88a20 && python3 tools/mkadt_pandora.py out.adt
ModuleNotFoundError: No module named 'adt'
```

按 `mkadt_pandora.py:4` 的出处说明（`Derived from ios-sweet tools/mkadt.py (dipa-studio/ios-sweet 425b2510)`），从 ios-sweet 同版本取回：

```
https://api.github.com/repos/dipa-studio/ios-sweet/contents/tools/adt.py
sha 9d7f259c92710167ab16667485f9eaa8b563518d  4185 bytes
```

放在 `tools/adt.py`。**这是补缺，不是改动上游设计**，所以没写进 `popsicle-adapt.patch`（patch 只管我们的适配），单独留作文件。

补上之后 ADT 能生成了，几何也验证落地：

```
$ python3 tools/mkadt_pandora.py out.adt --dump
  display-subsystem: canvas-width = 0x465 (1125)   ← iPhone X 逻辑画面，故意不动
                     canvas-height = 0x984 (2436)
   framebuffer0:      width  = 0x4b0 (1200)   ← 本机面板
                      height = 0xa30 (2608)
                      stride = 0x12c0 (4800)
  （另有一条 warning: /opt/work/ipsw/d22ap.adt missing, no /product node
    —— 缺 IPSW 里的官方 ADT 做 product 节点模板，上游本来就这样，
    不影响几何与内存段，等有 IPSW 放进去即可）
```

**遗留**：`mkadt_pandora.py` 里还有两处 pandora 专属路径写死 `/opt/work/...`（`d22ap.adt`、日志/固件 extents 的输入），换机器跑 ADT 前要把 IPSW 放到对应位置或改这两个常量。

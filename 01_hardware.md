# Homelab Cluster — Hardware Choices

3-node Raspberry Pi 5 Kubernetes cluster, all nodes control-plane (HA, every node runs etcd). Mounted in a 10" 2U
half-rack, NVMe-booted.

## Bill of materials

| Component    | Choice                                                    | Qty                   | OEM / reference                                                         |
|--------------|-----------------------------------------------------------|-----------------------|-------------------------------------------------------------------------|
| SBC          | Raspberry Pi 5, 8GB                                       | 3 (4th slot reserved) | [raspberrypi.com](https://www.raspberrypi.com/products/raspberry-pi-5/) |
| Enclosure    | GeeekPi 10" 2U rack (4-bay, bundled N04 NVMe adapters)    | 1                     | [wiki.deskpi.com](https://wiki.deskpi.com/rackmate_accessories_3/)      |
| NVMe adapter | N04 PCIe-to-M.2 (bundled with rack)                       | 4                     | [wiki.52pi.com](https://wiki.52pi.com/index.php?title=EP-0210)          |
| SSD          | Crucial P310 1TB 2280, w/o heat spreader (CT1000P310SSD5) | 1                     | [crucial.com](https://eu.crucial.com/ssd/p310/ct1000p310ssd8)           |
| PSU          | GeeekPi 27W USB-C PD (5.1V/5A)                            | 3                     | [amazon.se](https://www.amazon.se/dp/B0CQ1Q18HX)                        |
| Cooling      | Pi 5 active cooler (fan + alu heatsink)                   | 3                     | [raspberrypi.com](https://www.raspberrypi.com/products/active-cooler/)  |

---

## Compute — 3× Raspberry Pi 5 (8GB)

- **8GB** for headroom: control-plane + etcd + actual workloads on each node.
- **3 nodes** = odd etcd quorum, tolerates 1 failure. A 4th board exists but stays out for now — 4 control-plane nodes
  give the *same* fault tolerance as 3 while adding etcd write latency.
- 4th rack slot left open for a future non-cp worker (worker doesn't touch quorum).

## Enclosure — GeeekPi 10" 2U half-rack

- Holds up to 4 Pi 5 boards; Since I have a 10" rack at home, the 10" version was the natural choice.
- **Ships with 4× N04 PCIe-to-M.2 adapters** — NVMe per node without buying separate HATs.

## NVMe — bundled N04 adapters

- M.2 M-key, 2230–2280; using **2280**.
- Pi 5 PCIe is a **single Gen2 lane (~450 MB/s)**. Staying Gen2 — Gen3 is forceable (`dtparam=pciex1_gen=3`, ~800–900
  MB/s) but officially unsupported and risks AER errors in a tight thermal box. Light IO --> Gen2 is plenty for our
  use-case.
- N04 has an onboard 3.3V regulator (up to 3A), so **1TB single-sided drives are the safe power envelope**;
  larger, double-sided, power-hungry drives may draw too much current through the FPC cable and cause instability.

## Storage — Crucial P310 1TB (without heat spreader)

Model **CT1000P310SSD8**, M.2 2280, ~**220 TBW** ~ 1600.00 SEK (~ $170 USD)
** ([crucial](https://eu.crucial.com/ssd/p310/ct1000p310ssd8); NAND prices still elevated post-2024 shortage).

- **Endurance is the binding spec, not speed.** All nodes are control-plane → every node runs etcd → constant fsync/WAL
  writes. TBW is what matters here.
- **Rejected Crucial E100 (~80 TBW):** fine for light IO, but weak once *every* node is doing fsync-heavy etcd writes
  around the clock. P310's 220 TBW removes the question for little extra.
- **Skipped Gen4/Gen5:** the Pi throttles them to its Gen2 lane anyway, and Gen5 in particular runs hot in a stacked
  enclosure. PCIe gen is a link property, not worth the heat penalty.
- **Heat spreader had to come off.** I first bought one piece of the CT1000P310SSD5 model that came with an attached
  heat-sink. But Even at 2.3 mm, the spreader didn't clear between the N04 adapter and the Pi mounted above it, so I
  pried it off and the drive runs bare. Fine thermally: throttled to the Pi's Gen2 lane under light IO, the P310 barely
  warms up. For the other two drives, I resorted to the same model without the spreader (CT1000P310SSD8) to avoid the
  hassle of peeling off the spreader on each.

## Power — 3× GeeekPi 27W USB-C PD

One PSU per Pi. No DC distribution board — simple and independent.

- **27W / 5.1V·5A PD** is the Pi 5 target: lets the board lift the 600mA downstream USB current cap
  (`usb_max_current_enable=1`) and gives headroom for NVMe and later mayhaps additional external hdds.
- **Picked compact bricks ("not too thick")** so they physically fit in/around the rack — bulky official-style bricks
  don't seat cleanly when you need three side by side.

## Cooling — Pi 5 active cooler + thermal pads

Blower-style active cooler (aluminium heatsink + PWM fan), one per board. Kit included **3 thermal pads**. Placement:

- **CPU — BCM2712 SoC: 1 pad.** Primary contact, the tallest die.
- **RP1 I/O chip (southbridge): 2 pads stacked.** RP1 sits *lower* than the SoC, so a single pad left the cooler
  rocking/not seating flat. Doubling the pad fills the height gap and levels the cooler so both chips get firm contact.
- **No pads on the remaining chips (e.g. PMIC).** Two reasons: only 3 pads in the kit, and those chips run *warm, not
  hot* — they're fine bare.

Why RP1 is the one that needs the second contact: it's the southbridge carrying USB / Ethernet / GPIO / PCIe I/O, the
second-warmest chip after the SoC, and the cooler's intended secondary contact point.

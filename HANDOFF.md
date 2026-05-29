# Frontier-GROOT 엘리베이터 버튼 누르기 — 핸드오프

이 문서는 다음 사람이 작업을 이어받을 수 있도록 작성된 진입점이다.
이 레포 자체는 코드가 없고, **3개 fork 를 묶는 글루**다. 코드는 각 fork 안에 있다.

---

## 1. 무엇을 하던 작업인가

Frontier 로봇이 엘리베이터 호출 버튼을 정확히 누르도록 NVIDIA GR00T VLA 를 fine-tune 하는 파이프라인.
시뮬레이션(Isaac Sim) 안에서 수집 → 변환 → 학습 → 추론까지 닫혀 있고, Orin 같은 외부 추론 보드는 사용하지 않는다.

파이프라인:
1. **수집** — Isaac Sim 에서 DiffIK teacher 가 자동으로 데모 N개를 만들어 HDF5 로 저장
2. **변환** — HDF5 → LeRobot v2.1 dataset 으로 변환 (float32, modality.json, episode index)
3. **학습** — Isaac-GR00T 의 launch_finetune.py 로 fine-tune
4. **추론** — Isaac Sim 안에서 3-process 구조 (model server + zenoh bridge + sim env) 로 실행

---

## 2. 빠르게 시작하기

```bash
git clone git@github.com:skysky0214/frontier_groot_handover.git
cd frontier_groot_handover
./setup.sh        # 3개 fork 를 동일 디렉토리에 clone + 올바른 브랜치 checkout
```

setup.sh 가 끝나면 `repos/` 아래 다음 세 디렉토리가 생긴다:
- `repos/Isaac-GR00T/`       — GR00T VLA 코드 (fine-tune + server)
- `repos/elevator_button_press_task/` — Isaac Sim 환경·로봇·teacher·inference_demos
- `repos/frontier_simulation/` — Zenoh 추론 브리지 + 엘리베이터 USD

---

## 3. 코드 위치 (3 fork)

| 영역 | 레포 (브랜치) | 주요 파일 |
|---|---|---|
| GR00T 학습·서버 | `skysky0214/Isaac-GR00T` (`frontier_groot`) | `gr00t/experiment/launch_finetune.py`, `gr00t/eval/run_gr00t_server.py`, `examples/omy_callbutton/omy_config.py` |
| Isaac Sim 환경 + teacher + inference_demos | `skysky0214/elevator_button_press_task` (`frontier_groot`) | `source/robotis_lab/.../assets/robots/Frontier.py`, `source/robotis_lab/.../simulation_tasks/.../elevator_call_v2_aux/`, `scripts/my_codes/diffik_teacher_jointpos_frontier.py`, `scripts/sim2real/imitation_learning/inference/inference_demos.py`, `scripts/data_conversion/hdf5_to_v1.py`, `configs/modality/omy_config.py` |
| Sim ↔ GR00T 서버 브리지 + USD | `ROBOTIS-move/frontier_simulation` (`feature-zenoh-inference-groot`) | `script/isaac_sim/zenoh/zenoh_inference.py`, `script/isaac_sim/zenoh/policies/groot_policy.py`, `source/isaac_sim/assets/elevator/5_floor.usd` |

> `frontier_simulation` 은 ROBOTIS-move 내부 레포라 access 권한이 필요하다. 다음 사람이 같은 조직 멤버인지 확인.

---

## 4. 데이터·체크포인트·자산 위치

전부 **DataCrunch NFS 볼륨**에 있다 — 별도 다운로드 안 해도 같은 NFS 를 마운트하면 즉시 사용 가능.

NFS: `nfs.fin-03.datacrunch.io:/Dataset-789fd28b` (480GB, 자주 거의 꽉 참 — 큰 쓰기 전 `df -h` 확인)
마운트 경로: `/mnt/Dataset`

| 자원 | 경로 |
|---|---|
| Raw HDF5 demos | `/mnt/Dataset/frontier_top16_bellytuned_40/`, `/mnt/Dataset/frontier_top16_bellytuned_40_ledfix/`, `/mnt/Dataset/frontier_wide_jitter_40/` |
| LeRobot v2.1 datasets | `/mnt/Dataset/evButtonPush_top16_bellytuned_40_v1/`, `/mnt/Dataset/evButtonPush_ledfix_40_v1/`, `/mnt/Dataset/evButtonPush_wide_jitter_30_v1/`, `/mnt/Dataset/evButtonPush_combined_73_v1/` |
| Live GR00T 워크트리 (학습/서버 실행) | `/mnt/Dataset/Isaac-GR00T/` |
| Modality configs (live) | `/mnt/Dataset/gr00t_configs/omy_config.py`, `omy_config_wristonly.py` |
| HDF5 → v1 변환기 (live) | `/mnt/Dataset/hdf5_to_v1.py` |
| Checkpoints | `/mnt/Dataset/checkpoints_top16_bellytuned_40/` (base, checkpoint-1500), `/mnt/Dataset/checkpoints_ledfix/` (ckpt-1200, view_dropout best), `/mnt/Dataset/checkpoints_widejitter/` (ckpt-3500, wide spawn), `/mnt/Dataset/checkpoints_combined/` (in-progress) |
| TRT 자산 (GPU-specific, 재빌드 가능) | `/mnt/Dataset/trt_widejitter_ckpt3500/` |

> NFS 의 `Isaac-GR00T`, `gr00t_configs`, `hdf5_to_v1.py` 는 fork 의 동일 파일과 **별도 사본**이다. fork 가 진실의 출처(source of truth); NFS 는 학습이 실제로 돌아가는 working tree. 둘이 어긋나면 fork 의 최신을 NFS 로 sync 한 뒤 학습 재개.

---

## 5. 4단계 재현 (E2E)

베이스 가정: DataCrunch 인스턴스(RTX PRO 6000 Blackwell 또는 동급) + NFS 마운트 + `isaac-sim-custom:5.1.0` 컨테이너 가동. 셋업 상세는 6절.

### STEP 1 — 수집 (Isaac Sim 안)

```bash
# 컨테이너 내부, /workspace/robotis_lab 또는 fork 의 elevator_button_press_task
python scripts/my_codes/diffik_teacher_jointpos_frontier.py \
  --N 40 \
  --robot-lateral-jitter 0.05 --robot-depth-jitter 0.05 \
  --out /mnt/Dataset/frontier_<run-name>/
# 출력: HDF5 demos (5-phase: approach/press/hold/retract/home)
```

### STEP 2 — 변환

```bash
python scripts/data_conversion/hdf5_to_v1.py \
  --in  /mnt/Dataset/frontier_<run-name>/ \
  --out /mnt/Dataset/evButtonPush_<run-name>_v1/
# 출력: LeRobot v2.1 (modality.json + parquet + 영상)
```

### STEP 3 — 학습

```bash
# Isaac-GR00T fork (frontier_groot 브랜치) 안에서
python gr00t/experiment/launch_finetune.py \
  --dataset_path /mnt/Dataset/evButtonPush_<run-name>_v1/ \
  --output_dir   /mnt/Dataset/checkpoints_<run-name>/ \
  --max_steps 2000 \
  --view_dropout 0.3      # 우리가 추가한 옵션
```

### STEP 4 — 추론 (3 프로세스, 같은 컨테이너 안)

각각 별도 셸에서 순서대로:

```bash
# Process A — GR00T 모델 서버 (ZMQ REP)
python gr00t/eval/run_gr00t_server.py \
  --ckpt /mnt/Dataset/checkpoints_widejitter/.../checkpoint-3500 \
  --modality examples/omy_callbutton/omy_config.py
# (옵션) TRT 가속: --trt_engine_path /mnt/Dataset/trt_widejitter_ckpt3500/dit_model_bf16.trt

# Process B — Zenoh 브리지 (sim ↔ server 중계)
python script/isaac_sim/zenoh/zenoh_inference.py --policy groot --use_frontier

# Process C — Isaac Sim 환경 + 평가
python scripts/sim2real/imitation_learning/inference/inference_demos.py \
  --auto_eval --dump_inference
```

3개 모두 떠 있어야 동작. zenoh 브리지를 안 띄우면 inference_demos 가 env.step 까지 도달 안 함(이전 디버깅 사례).

---

## 6. 환경 셋업

### GPU 요구사항

- **OK**: RTX PRO 6000 Blackwell Server Edition (SM 12.0) — 우리가 쓰던 것
- **불가**: NVIDIA B300 (SM 10.3) — Isaac Sim 의 bundled CUDA 12.8 nvrtc 가 SM 10.3 미지원. `TORCH_CUDA_ARCH_LIST` / `PYTORCH_JIT=0` 우회 모두 실패. DataCrunch VM 선택 시 주의.

### NFS 마운트

```bash
sudo mkdir -p /mnt/Dataset
sudo mount -t nfs -o nconnect=16 nfs.fin-03.datacrunch.io:/Dataset-789fd28b /mnt/Dataset
```

### 컨테이너

이미지: `isaac-sim-custom:5.1.0` (27.3GB). 이미 호스트에 있으면 `docker start isaac-sim` 으로 켜짐.
**NFS 가 호스트에 마운트된 뒤에 컨테이너를 켜야** `/mnt/Dataset` 이 컨테이너 안에서 보인다. 순서 거꾸로 가면 재시작.

### fake nvcc shim (deepspeed 용)

```bash
mkdir -p /tmp/fake_cuda/bin
echo '#!/bin/bash' > /tmp/fake_cuda/bin/nvcc
chmod +x /tmp/fake_cuda/bin/nvcc
export PATH=/tmp/fake_cuda/bin:$PATH
```

컨테이너 재시작 시 사라지므로 매번 재생성.

### gh / git 인증

서버에는 SSH key 가 GitHub `skysky0214` 로 연결돼 있다(`ssh -T git@github.com` 으로 확인). 새 인스턴스면 key 재등록 필요.

---

## 7. 진행 상태 / 다음 할 일

마지막 마일스톤:
- widejitter 학습 완료(ckpt-3500). combined(73 demos) 학습 진행 중.
- view_dropout(=0.3) 변종이 ledfix 에서 최고 성능 (ckpt-1200).
- TRT 변환 가능 확인(`trt_widejitter_ckpt3500/dit_model_bf16.trt`), Blackwell 전용 엔진.

다음 후보:
- `inference_demos.py` 추가 모듈화(현재 1802 줄, /tmp/il_pr/ 에 작업본 있음 — 아직 PR 미발행)
- combined 체크포인트 평가
- HF 업로드(데이터·체크포인트) — 본 핸드오프에는 빠짐, NFS 그대로 사용
- 실기 로봇 이식 검토 (현재까지 모든 추론은 Isaac Sim 안)

---

## 8. 알려진 이슈

- **NFS 가 거의 꽉 참** (26GB 여유). 새 체크포인트 저장 전 `du -sh /mnt/Dataset/*` 로 큰 폴더 청소.
- **checkpoint-1600 부패 케이스** — NFS 가 학습 중 꽉 차서 빈 ckpt 가 생성됨. 디스크 여유 확인 + 저장 전 사이즈 sanity check.
- **Zenoh 브리지 미기동 시 추론 침묵 실패** — inference_demos 가 env.step 까지 안 들어가고 dump 가 빈다. 3-process 순서 지킬 것.
- **docker commit / containerd 이미지 스토어 손상** — 이전에 image layer digest 손실로 commit 실패. `docker export` (live FS 읽음) 가 우회로.
- **`*.usd` 가 robotis_lab .gitignore 에 포함** — fork 에 USD 추가할 일 있으면 `git add -f` 또는 .gitignore 예외 추가. 5_floor.usd 는 frontier_simulation 쪽에 -f 로 들어가 있음.
- **컨테이너 내부 git 미설치** — git 작업은 호스트에서.
- **`elevator_button_press_task` clone 시 LFS 경고** — `source/robotis_lab/data/{object,robots}/*.usd` 16개가 "should have been pointers but weren't" 로 뜸. 이전 작업물(우리 변경과 무관). 실제 파일은 존재하지만 LFS 추적 메타와 어긋난 상태. 그 USD 들을 실제로 쓸 때 문제 생기면 LFS pull 또는 .gitattributes 정리.

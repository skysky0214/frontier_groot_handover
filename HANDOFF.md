# Frontier-GR00T 엘리베이터 누르기 인수인계

이 레포 자체엔 코드가 없다. clone 하고 `./setup.sh` 만 돌리면 세 레포가 알맞은 브랜치로
받아져서 작업 환경이 복원된다.

## 뭐 하던 작업인지

Frontier 로봇이 엘리베이터 호출 버튼을 정확히 누르도록 NVIDIA 의 GR00T VLA(N1.6) 를
fine-tune 하는 파이프라인이다. 시뮬레이션 안에서 데모 수집 → LeRobot 데이터셋 변환 →
학습 → 다시 시뮬 안에서 추론·평가까지 한 환경에서 닫혀 있다. Orin 이나 실기 로봇으로는
아직 안 옮겼다.

추론은 세 프로세스로 동작한다. GR00T 모델 서버, Zenoh 기반 통신 브리지, Isaac Sim 환경.
셋이 다 떠 있어야 한 스텝이 돈다.

## 빠르게 시작

```bash
git clone git@github.com:skysky0214/frontier_groot_handover.git
cd frontier_groot_handover
./setup.sh
```

`setup.sh` 가 세 fork 를 `repos/` 아래에 받아 알맞은 브랜치로 체크아웃한다. 그 다음 NFS
마운트하고 컨테이너 띄우고 4단계 파이프라인을 돌리는 순서다. 환경 셋업 자세한 건 아래에.

## 코드 위치

세 레포에 흩어져 있다.

**`skysky0214/Isaac-GR00T` (브랜치 `frontier_groot`)** — GR00T 모델 코드. NVIDIA upstream
의 `n1.6-release` 태그 위에 5 커밋 얹은 것뿐이다. 추가한 건 `view_dropout` 옵션, TRT 엔진
경로 옵션, model forward 의 timing 로깅, OMY 모달리티 예시 폴더 정도.

**`skysky0214/elevator_button_press_task` (브랜치 `frontier_groot`)** — robotis_lab fork.
이름이 좀 안 맞는데(ACT IL 시절 fork 떴을 때 그 task 만 신경 써서 그렇게 지었던 게 그대로
남았음), 그냥 robotis_lab fork 라고 생각하면 된다. 안에 들어가는 것: Frontier 로봇 자산
(`source/.../assets/robots/Frontier.py`), GR00T 용 task 정의
(`source/.../OMY/elevator_call_v2_aux/`), HDF5→LeRobot 변환기
(`scripts/data_conversion/hdf5_to_v1.py`), 추론 환경 운영 스크립트
(`scripts/sim2real/imitation_learning/inference/inference_demos.py` + 같은 디렉토리의
`inference_helpers/` 패키지), 그리고 모달리티 config (`configs/modality/`).

**`ROBOTIS-move/frontier_simulation` (두 브랜치)** — 회사 내부 레포라 ROBOTIS-move org 접근
권한이 필요하다. 데모 수집 teacher 코드는 `feature-frontier-teacher` 브랜치에 PR #15 로
modularized 패키지(`script/isaac_sim/example/diffik_teacher_jointpos_frontier.py` +
`frontier_helpers/`) 형태로 올라가 있다. GR00T 추론용 Zenoh 브리지와 5층 엘리베이터 USD 는
`feature-zenoh-inference-groot` 브랜치 (`script/isaac_sim/zenoh/zenoh_inference.py`,
`policies/groot_policy.py`, `source/isaac_sim/assets/elevator/5_floor.usd`).

robotis_lab fork 에는 ACT IL 시절 만들어둔 자산(옛 teacher 두 개, 옛 `elevator_call` task,
ACT 학습 체크포인트 약 376MB)이 그대로 남아 있다. GR00T 파이프라인은 안 쓰지만 이전 결과
재현용으로 일부러 안 지웠다.

## 데이터·체크포인트는 NFS 에

전부 DataCrunch NFS 볼륨(`nfs.fin-03.datacrunch.io:/Dataset-789fd28b`)에 있다. VM 인스턴스가
바뀌어도 NFS 는 살아남는다. 컨테이너든 호스트든 `/mnt/Dataset` 으로 마운트한다.

- Raw HDF5 데모: `frontier_top16_bellytuned_40/`, `..._ledfix/`, `frontier_wide_jitter_40/`
- LeRobot v2.1 변환본: `evButtonPush_*_v1/` 4종 (top16/ledfix/widejitter/combined)
- 학습이 실제로 도는 working tree: `/mnt/Dataset/Isaac-GR00T/`. fork 와 별도 사본이고,
  fork 가 진실의 출처. 학습 전 sync 필요.
- 학습이 실제로 읽는 모달리티: `/mnt/Dataset/gr00t_configs/omy_config.py`. fork 의
  `configs/modality/omy_config.py` 와 별도 사본 — 이것도 변경 시 둘 다.
- 체크포인트: `checkpoints_widejitter/.../checkpoint-3500` 이 마지막 안정 가중치.
  `checkpoints_ledfix/.../checkpoint-1200` (view_dropout=0.3) 가 단일 데이터셋 베스트.
  `checkpoints_combined/` 는 학습 진행 중이었음 (ckpt-500 정도).
- TRT 엔진: `trt_widejitter_ckpt3500/dit_model_bf16.trt`. Blackwell GPU 전용 — 다른 GPU 면
  다시 빌드해야 한다 (`Isaac-GR00T/scripts/deployment/build_tensorrt_engine.py`).

NFS 용량이 빠듯하다. 480GB 중 보통 20-30GB 정도밖에 안 남아 있어서 새 체크포인트 저장 전
`df -h /mnt/Dataset` 한 번씩 보고 정리해야 한다. 한 번 학습 도중에 NFS 가 꽉 차서 ckpt-1600
이 빈 파일로 저장된 적이 있다.

## 한 사이클 돌리는 법

### 1. 데모 수집

```bash
# frontier_simulation 의 teacher 사용 (PR #15)
python script/isaac_sim/example/diffik_teacher_jointpos_frontier.py \
  --N 40 \
  --robot-lateral-jitter 0.05 --robot-depth-jitter 0.05 \
  --out /mnt/Dataset/frontier_<run>/
```

5-phase trajectory (approach → press → hold → retract → home) 로 N 개 에피소드를 자동 수집.
출력은 HDF5 한 파일에 모든 에피소드.

### 2. LeRobot v2.1 로 변환

```bash
# robotis_lab fork
python scripts/data_conversion/hdf5_to_v1.py \
  --in  /mnt/Dataset/frontier_<run>/ \
  --out /mnt/Dataset/evButtonPush_<run>_v1/
```

float32 강제, `modality.json` 작성, 영상 재인코딩.

### 3. fine-tune

```bash
# Isaac-GR00T fork 안에서
python gr00t/experiment/launch_finetune.py \
  --dataset_path /mnt/Dataset/evButtonPush_<run>_v1/ \
  --output_dir   /mnt/Dataset/checkpoints_<run>/ \
  --max_steps 2000 \
  --view_dropout 0.3
```

`view_dropout` 은 우리가 추가한 옵션. wrist 카메라 의존을 줄이려고.

### 4. 추론 (3 프로세스, 순서 중요)

같은 컨테이너 안에서 셸 셋으로 띄운다. A → B → C 순서.

```bash
# A. GR00T 모델 서버 (ZMQ REP)
python gr00t/eval/run_gr00t_server.py \
  --ckpt /mnt/Dataset/checkpoints_widejitter/.../checkpoint-3500 \
  --modality examples/omy_callbutton/omy_config.py
# TRT 가속 옵션: --trt_engine_path .../dit_model_bf16.trt

# B. Zenoh 브리지 (sim ↔ server 중계)
python script/isaac_sim/zenoh/zenoh_inference.py --policy groot --use_frontier

# C. Isaac Sim 환경 + 평가
python scripts/sim2real/imitation_learning/inference/inference_demos.py \
  --auto_eval --dump_inference
```

B 안 띄우고 C 만 띄우면 `inference_demos` 가 첫 `env.step` 도 못 들어간다. 침묵 실패라
한참 헤맬 수 있다 — 이거 디버깅하느라 시간 꽤 썼다.

### 추론 속도 참고

B300 GPU 1장 + chunk_len=16 기준으로 한 번 측정해봤다.

- 모델 forward: ~170ms (BF16, diffusion 4 step)
- 환경 step: ~72ms
- 한 chunk cycle: ~1155ms → 실효 replan rate 0.87Hz

GR00T 자체는 6Hz 까지 가능한데 chunk_len 이 크면 replan 이 자주 안 일어난다. chunk_len 을
3 으로 줄이면 4.6Hz 까지 올라가고 reactive 해진다 (GPU 활용도 78%). 더 자세한 표는
`/home/ub/cosmos_run12/groot_inference_pkg/README.md` 에 있다.

## 환경

DataCrunch GPU 인스턴스에서 돈다. VM IP 가 자주 바뀌어서 `~/.ssh/config` 에 alias
(`Gaemi_1`) 로 관리. SSH 키는 GitHub `skysky0214` 와 묶여 있다.

```bash
# NFS 마운트 (호스트)
sudo mkdir -p /mnt/Dataset
sudo mount -t nfs -o nconnect=16 nfs.fin-03.datacrunch.io:/Dataset-789fd28b /mnt/Dataset

# 컨테이너 (이미지 isaac-sim-custom:5.1.0)
docker start isaac-sim
```

NFS 가 호스트에 먼저 마운트된 다음 컨테이너를 켜야 컨테이너 안에서 `/mnt/Dataset` 이
보인다. 순서 거꾸로 가면 컨테이너 재시작.

GPU 는 RTX PRO 6000 Blackwell (SM 12.0) 정도면 잘 돈다. **B300 (SM 10.3) 은 피할 것** —
Isaac Sim 의 bundled CUDA 12.8 nvrtc 가 SM 10.3 을 지원 안 한다. `TORCH_CUDA_ARCH_LIST` 도,
`PYTORCH_JIT=0` 도 우회 안 됐다. VM 잡을 때 GPU 모델 꼭 확인.

DeepSpeed 가 빌드 시 `nvcc` 를 찾는데 컨테이너에 nvcc 가 없다. fake shim 을 매번 만들어
주면 우회된다 (컨테이너 재시작 시 사라지니 다시 만들어야 함):

```bash
mkdir -p /tmp/fake_cuda/bin
echo '#!/bin/bash' > /tmp/fake_cuda/bin/nvcc
chmod +x /tmp/fake_cuda/bin/nvcc
export PATH=/tmp/fake_cuda/bin:$PATH
```

## 어디까지 됐는지

학습:

- widejitter (wide spawn jitter 30 데모) — ckpt-3500 까지 학습 완료. 가장 안정적인 가중치.
- ledfix (LED 정상화 40 데모) — ckpt-1200, view_dropout=0.3 변종이 단일 데이터셋 베스트.
- combined (ledfix + widejitter, 73 ep) — 학습 진행 중이었음 (ckpt-500 부근).
- TRT 변환 — `trt_widejitter_ckpt3500/dit_model_bf16.trt` 로 빌드 성공 확인. Blackwell 전용.

코드:

- `inference_demos.py` 모듈화 완료. 원래 1814 줄짜리 한 파일이었는데 888 줄 +
  `inference_helpers/` 패키지(viz, dump, ik_fallback, elevator_5floor, collision,
  env_setup, frontier_setup) 로 쪼개졌다.
- 절대 경로는 env var 로 빼서 다른 머신에서도 동작하도록 (`FRONTIER_USD_PATH`,
  `ELEVATOR_USD_DIR`, `INFERENCE_DUMP_DIR` 등).
- 운영 로그가 너무 많아서 `_log` wrapper 로 묶고 `VERBOSE=0` 으로 입막음 가능하게 함.

남은 거:

- combined 학습 마저 끝내고 평가
- HuggingFace Hub 업로드 (지금은 NFS 사본만). 인스턴스가 죽으면 NFS 도 같이 위태로워서,
  진짜 가치 있는 ckpt 와 데이터셋은 HF 로 옮기는 게 안전하다.
- 실기 로봇 이식 검토. 지금까지는 다 시뮬 안. sim2real gap, latency, contact 처리 등.

## 다음 사람이 헷갈릴 만한 것들

**fork 이름이 일관성 없다.** robotis_lab fork 의 이름이 `elevator_button_press_task`. ACT IL
시절 fork 떴을 때 그 task 만 신경 써서 그렇게 지었던 게 그대로 남았다. 안에 들어가는 건
robotis_lab 전체 트리.

**같은 파일이 두 군데 있는 경우가 종종 있다.**

- 모달리티 config: fork 의 `configs/modality/omy_config.py` 와 NFS 의
  `/mnt/Dataset/gr00t_configs/omy_config.py`. 학습은 NFS 쪽을 읽는다. 변경 시 둘 다.
- Isaac-GR00T 본체: fork (`skysky0214/Isaac-GR00T`) 와 NFS (`/mnt/Dataset/Isaac-GR00T`).
  학습은 NFS 쪽을 돌린다. fork 가 진실의 출처라고 두고 학습 전 sync.

**OMY task 가 두 가지가 같이 있다.** `source/.../OMY/` 안에 옛 `elevator_call/` 과 GR00T 용
`elevator_call_v2_aux/` 가 공존한다. GR00T 파이프라인은 무조건 `_v2_aux` (gym ID 에 `-Aux-`
붙은 것). 구버전은 ACT IL 시절 결과 재현용으로 남겨뒀다.

**3-프로세스 추론은 순서가 있다.** A(server) → B(zenoh) → C(inference_demos). B 안 띄우면
C 가 침묵 실패하는데 에러 메시지가 거의 없어서 한참 모를 수 있다.

**ACT IL 자산이 fork 에 그대로 남아 있다.** `scripts/act/`, `scripts/imitation_learning/act/`,
`task/`, `source/.../OMY/elevator_call/`, `checkpoints/` (체크포인트만 376MB). GR00T 는 안
쓰지만 이전 ACT 학습 결과 재현 가능하게 일부러 안 지웠다. 필요 없다고 판단되면 따로 정리.

## 알아두면 도움 되는 함정들

NFS 용량이 학습 도중 차면 ckpt 가 빈 파일로 저장된다. `checkpoint-1600` 이 그렇게 죽었다.
저장 전에 `df` 한 번씩.

`docker commit` 이 한 번 깨진 적 있다. containerd image layer digest 가 손상돼서. 우회는
`docker export` — live FS 를 읽으니 image store 안 거치고 빠져나온다.

`.gitignore` 에 `*.usd` 가 있어서 fork 에 USD 추가하려면 `git add -f`. `5_floor.usd` 가
그렇게 들어갔다 (58KB 작아서 LFS 안 썼다).

컨테이너 안에 git 이 안 깔려 있다. git 작업은 호스트에서.

DataCrunch VM 이 바뀌면 같은 IP 에 다른 호스트 키가 들러붙어서 SSH 가 거부할 때가 있다.
`ssh-keygen -R <ip>` 후 재접속.

`elevator_button_press_task` 를 clone 하면 `data/object/*.usd` 16개에 대해 "should have
been pointers but weren't" LFS 경고가 뜬다. 우리 변경 아니고 옛 작업물 — 그 USD 들을 실제
쓸 일 있으면 LFS 정리가 필요하지만 GR00T 파이프라인엔 영향 없다.

---

추론 파이프라인을 코드 기준으로 더 자세히 보고 싶으면
`/home/ub/cosmos_run12/groot_inference_pkg/` 안 README 가 도움이 된다. timing, chunk_len
trade-off, 데이터 흐름 다이어그램이 정리돼 있다.

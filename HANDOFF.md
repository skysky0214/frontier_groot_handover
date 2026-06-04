# Frontier-GR00T 엘리베이터 버튼 누르기 — 인수인계

## 이 문서를 읽기 전에

시뮬에서 로봇이 버튼 누르는 장면을 자동으로 녹화
    → 녹화 데이터를 학습 형식으로 변환
        → AI 모델(GR00T)을 그 데이터로 fine-tune
            → 시뮬에서 학습된 모델로 실제 동작 평가


코드는 전혀 없는 **인수인계 전용 레포**이고, `./setup.sh` 한 번으로 실제 코드가 담긴 세 레포가 자동으로 받아진다.

---

## 프로젝트 개요

### 무엇을 만드는가

ROBOTIS의 **Frontier** 로봇(바퀴 달린 모바일 베이스 위에 OMY 6축 로봇팔이 얹힌 형태)이 실내에서 엘리베이터 호출 버튼을 정확히 누르도록 학습시키는 것이 목표다.

학습 모델은 NVIDIA의 **GR00T VLA**(Vision-Language-Action 모델, N1.6 릴리스)를 우리 데이터로 fine-tune한 것이다.

### 전체 흐름이 시뮬 안에서 닫혀 있다

실제 로봇 없이 Isaac Sim 시뮬레이터 안에서 모든 과정이 돌아간다.

- **데모 수집**: IK(역기구학) 기반 teacher 스크립트가 자동으로 로봇 시연 영상을 생성
- **데이터 변환**: 수집된 데이터(HDF5)를 LeRobot v2.1 포맷으로 변환
- **학습**: GR00T 모델을 그 데이터로 fine-tune
- **평가**: 시뮬을 다시 띄워서 학습된 모델이 버튼을 제대로 누르는지 확인

---

## 빠른 시작

```bash
git clone git@github.com:skysky0214/frontier_groot_handover.git
cd frontier_groot_handover
./setup.sh
```

`setup.sh`가 아래 세 레포를 `repos/` 아래 받고 올바른 브랜치로 체크아웃한다.

이후 순서: **환경 변수 설정 → 인프라 기동 → 4단계 파이프라인**

---

## 환경 변수 먼저 설정하기

하드코딩된 경로 대신, 아래 변수를 본인 환경에 맞게 채운 뒤 셸에 export하자. 이후 모든 명령어는 이 변수를 참조한다.

```bash
# ── 데이터 루트 (학습 데이터, 변환본, 체크포인트가 모두 모이는 곳) ─────────
export DATA_ROOT="/path/to/your/dataset"          # 예: /mnt/Dataset

# ── 이번 작업 이름 (수집 run, 데이터셋, 체크포인트 폴더명에 쓰임) ──────────
export RUN_NAME="run_001"                          # 원하는 이름 자유 지정
export DATASET_NAME="evButtonPush_${RUN_NAME}"    # 변환된 데이터셋 폴더명

# ── 체크포인트 ───────────────────────────────────────────────────────────────
export CKPT_DIR="${DATA_ROOT}/checkpoints_${RUN_NAME}"
export CKPT_STEP="step_2000"                       # 실제 저장된 step 이름으로 교체

# ── TensorRT 엔진 (Blackwell GPU용, 없으면 BF16 모드로 실행) ─────────────────
export TRT_ENGINE="${DATA_ROOT}/trt_${RUN_NAME}/dit_model_bf16.trt"

# ── GR00T 코드 루트 ──────────────────────────────────────────────────────────
export GROOT_ROOT="${DATA_ROOT}/Isaac-GR00T"      # NFS working tree 경로
```

---

## 코드 구조 

코드가 세 레포에 흩어져 있는데, 각각 다른 upstream(NVIDIA, ROBOTIS, 사내)을 따라가야 해서 하나로 합칠 수 없었다.

### 1. `skysky0214/Isaac-GR00T` (브랜치: `frontier_groot`)

NVIDIA가 공개한 [Isaac-GR00T](https://github.com/NVIDIA/Isaac-GR00T)의 fork.

`n1.6-release` 태그 위에 5개 커밋만 추가한 가벼운 변경이다. 우리가 추가한 것:

- `view_dropout` 옵션: 학습 중 카메라 view를 무작위로 가려서 모델이 특정 카메라에 과의존하지 않게 함
- TensorRT 엔진 경로 옵션
- 모델 forward 타이밍 로깅
- OMY 로봇용 모달리티 config 예시 (`configs/modality/omy_config.py` 등)

### 2. `skysky0214/elevator_button_press_task` (브랜치: `frontier_groot`)

ROBOTIS가 공개한 [robotis_lab](https://github.com/ROBOTIS-GIT/robotis_lab)의 fork.

GR00T용으로 우리가 추가·수정한 주요 파일:

| 파일/폴더 | 설명 |
|---|---|
| `source/.../assets/robots/Frontier.py` | Frontier 로봇 자산 정의 (USD 경로, 관절 한계, 액추에이터 등) |
| `source/.../OMY/elevator_call_v2_aux/` | GR00T 학습용 Isaac Lab task 정의 (버튼의 카메라 픽셀 좌표 등 보조 관측 포함) |
| `scripts/data_conversion/hdf5_to_v1.py` | 수집된 HDF5 → LeRobot v2.1 변환 스크립트 |
| `scripts/sim2real/imitation_learning/inference/inference_demos.py` | 학습된 정책 평가 스크립트 (888줄, 7개 helper 모듈로 모듈화 완료) |
| `configs/modality/omy_config.py` 등 | GR00T 모달리티 정의 (카메라 3개, state, action 차원) |

> **task가 두 개 공존한다.** `source/.../OMY/elevator_call/`(구버전)과 `elevator_call_v2_aux/`(GR00T용)이 둘 다 있다. **GR00T 파이프라인은 반드시 `_v2_aux` 쪽**을 써야 한다. gym ID에 `-Aux-`가 붙어 있으면 맞다. 구버전은 ACT 시절 재현용으로 남겨뒀다.

### 3. `ROBOTIS-move/frontier_simulation` (사내 레포, 두 브랜치)

ROBOTIS-move org 멤버만 접근 가능. 두 브랜치를 각각 다른 목적으로 사용한다.

| 브랜치 | 역할 |
|---|---|
| `feature-frontier-teacher` | 데모 수집 teacher 스크립트 (PR #15). 진입점: `script/isaac_sim/example/diffik_teacher_jointpos_frontier.py` + `frontier_helpers/` 패키지 |
| `feature-zenoh-inference-groot` | 추론 시 시뮬↔모델 서버 연결용 Zenoh 브리지 + 5층 엘리베이터 USD 자산 |

---

## 4단계 파이프라인

환경 변수를 export한 상태에서 실행한다.

### 1단계 — 데모 수집

```bash
python script/isaac_sim/example/diffik_teacher_jointpos_frontier.py \
  --N 40 \
  --robot-lateral-jitter 0.05 \
  --robot-depth-jitter 0.05 \
  --out ${DATA_ROOT}/${RUN_NAME}/
```

5단계 trajectory(approach → press → hold → retract → home)로 40개 에피소드를 자동 생성한다.

`--robot-*-jitter` 옵션: 로봇 초기 위치를 무작위화해서 데이터 다양성을 높인다. 값을 키울수록 더 넓은 범위에서 시작 위치가 흩어진다.

### 2단계 — LeRobot v2.1 변환

```bash
python scripts/data_conversion/hdf5_to_v1.py \
  --in  ${DATA_ROOT}/${RUN_NAME}/ \
  --out ${DATA_ROOT}/${DATASET_NAME}_v1/
```

float32 강제, `modality.json` 작성, 영상 재인코딩까지 한 번에 처리한다.

### 3단계 — Fine-tune

```bash
python gr00t/experiment/launch_finetune.py \
  --dataset_path ${DATA_ROOT}/${DATASET_NAME}_v1/ \
  --output_dir   ${CKPT_DIR}/ \
  --max_steps 2000 \
  --view_dropout 0.3
```

`view_dropout`은 우리가 추가한 옵션이다(NVIDIA 원본에 없음). 학습 중 카메라 view를 무작위로 가린다.

> **학습 전 디스크 여유 확인**: 체크포인트가 크기 때문에 저장 공간이 부족하면 ckpt가 빈 파일로 저장된다. 학습 시작 전 반드시 확인.
> ```bash
> df -h ${DATA_ROOT}
> ```

### 4단계 — 추론 및 평가

추론은 **3개의 프로세스를 순서대로** 띄워야 한다. 셸 3개를 열자.

```bash
# [셸 A] GR00T 모델 서버 먼저 실행
python gr00t/eval/run_gr00t_server.py \
  --ckpt ${CKPT_DIR}/${CKPT_STEP}/ \
  --modality examples/omy_callbutton/omy_config.py

# TRT 엔진이 있다면 아래 옵션 추가:
# --trt_engine_path ${TRT_ENGINE}
```

```bash
# [셸 B] A가 준비된 후 Zenoh 브리지 실행 (시뮬 ↔ 서버 중계)
python script/isaac_sim/zenoh/zenoh_inference.py --policy groot --use_frontier
```

```bash
# [셸 C] B가 준비된 후 Isaac Sim 환경 + 자동 평가 실행
python scripts/sim2real/imitation_learning/inference/inference_demos.py \
  --auto_eval --dump_inference
```

> ⚠️ **B를 빠뜨리면 C가 조용히 멈춘다.** 에러 메시지도 없이 첫 `env.step`에서 진행이 안 된다. 3개 프로세스 순서(A → B → C)를 꼭 지키자.

---

## 추론 속도 참고 (Blackwell GPU 1장 기준)

GR00T 모델과 시뮬이 비동기로 돌기 때문에, 모델이 한 번 추론하면 여러 step 분량의 action chunk를 반환하고 시뮬이 그걸 소화한다.

| 항목 | 수치 |
|---|---|
| 모델 forward | ~170ms (BF16, diffusion 4 step) |
| 시뮬 step | ~72ms |
| chunk_len=16 | 사이클 ~1.15초, replan rate 0.87Hz |
| chunk_len=3 | 4.6Hz, GPU 활용률 78% (추천 설정) |

`chunk_len`이 클수록 모델 호출이 줄고 동작이 부드러워지지만 반응이 느려진다. 작을수록 반응은 빠르지만 GPU가 자주 깨어난다.

자세한 타이밍 표와 데이터 흐름 다이어그램은 `groot_inference_pkg/README.md`를 참고.

---

## 환경 셋업 (DataCrunch 기준)

DataCrunch 외 환경이라면 NFS 마운트 부분만 자신의 스토리지에 맞게 바꾸면 된다.

```bash
# 1. NFS 마운트 (호스트에서 먼저, 컨테이너 기동 전)
sudo mkdir -p ${DATA_ROOT}
sudo mount -t nfs -o nconnect=16 <NFS_HOST>:/<NFS_VOLUME> ${DATA_ROOT}

# 2. 컨테이너 기동
docker start isaac-sim
```

> **순서 주의**: NFS를 호스트에 먼저 마운트한 뒤 컨테이너를 켜야 컨테이너 안에서 데이터 폴더가 보인다. 순서가 바뀌면 컨테이너를 재시작해야 한다.

### Python 패키지 의존성

컨테이너 기동 후, 데모 수집(1단계) 실행 전에 아래 패키지를 설치해야 한다. teacher 스크립트의 IK 계산에 사용된다.

```bash
pip install ikpy
```

컨테이너를 재시작해도 pip 설치는 유지되므로 최초 1회만 하면 된다.

### GPU 주의사항

- **권장**: RTX PRO 6000 Blackwell (SM 12.0) 계열
- **피할 것**: B300 (SM 10.3) — Isaac Sim의 bundled CUDA 12.8 nvrtc가 SM 10.3을 지원하지 않는다. `TORCH_CUDA_ARCH_LIST`나 `PYTORCH_JIT=0`으로도 우회되지 않는다.

DataCrunch에서 VM 신청 시 GPU 모델을 꼭 확인하자.

### DeepSpeed nvcc 우회 (컨테이너 재시작마다 필요)

학습에 쓰는 DeepSpeed가 빌드 시 `nvcc`를 찾는데 컨테이너에 없다. fake shim으로 우회한다.

```bash
mkdir -p /tmp/fake_cuda/bin
echo '#!/bin/bash' > /tmp/fake_cuda/bin/nvcc
chmod +x /tmp/fake_cuda/bin/nvcc
export PATH=/tmp/fake_cuda/bin:$PATH
```

컨테이너를 재시작하면 사라지므로, 학습 전마다 다시 실행해야 한다.

---

## 파일이 두 군데 있는 것들 (주의)

모달리티 config(`omy_config.py`)와 Isaac-GR00T 코드가 fork와 NFS working tree 두 군데에 각각 사본으로 존재한다.

- **fork**: 소스 컨트롤의 진실의 출처(source of truth)
- **NFS working tree**: 학습 스크립트가 실제로 읽는 파일

변경 시 **둘 다 동기화**해야 학습에 반영된다. 한쪽만 바꾸면 왜 반영이 안 되는지 한참 헤맬 수 있다.

---

## 현재 진행 상황

- 데이터 변형(스폰 jitter 범위, LED 처리 방식 등) 별로 여러 변종을 만들어 비교 중
- 일부 데이터셋을 합친 combined 학습이 진행 중이었으나 미완
- TensorRT 변환: 가장 안정적인 ckpt 하나로 빌드해서 동작 확인 완료
- 코드 정리 완료: 절대 경로 환경변수화, `inference_demos.py` 모듈화(888줄), 운영 로그 `VERBOSE=0` 제어 가능

### 남은 작업

- Combined 학습 완료 후 평가
- 가치 있는 ckpt와 데이터셋을 HuggingFace Hub으로 이전 (현재 NFS 사본만 존재, 인스턴스 장애 시 위험)
- 실기 로봇 이식 검토 — 현재까지 전부 시뮬. sim2real gap, latency, contact 처리 등 검증 필요

---

## 자주 걸리는 함정들

| 상황 | 원인 / 해결 |
|---|---|
| C(inference_demos)가 아무 반응 없이 멈춤 | B(Zenoh 브리지)를 안 띄운 것. A → B → C 순서 지키기 |
| 체크포인트가 빈 파일로 저장됨 | 학습 중 디스크 꽉 참. 학습 전 `df -h ${DATA_ROOT}` 확인 |
| fork에 USD 파일 추가 안 됨 | `.gitignore`에 `*.usd`가 있음. `git add -f`로 강제 추가 |
| 컨테이너 안에서 git 명령 안 됨 | 컨테이너에 git 미설치. git 작업은 호스트에서 |
| SSH 접속 거부 (VM 교체 후) | 같은 IP에 호스트 키가 바뀐 것. `ssh-keygen -R <ip>` 후 재접속 |
| `elevator_button_press_task` clone 시 LFS 경고 | `data/object/*.usd` 16개 관련. GR00T 파이프라인에는 영향 없음 |
| `docker commit` 실패 (image layer digest 손상) | `docker export`로 우회 (image store를 안 거침) |

---

## ACT 시절 자산에 대해

fork 안에 ACT(Action Chunking Transformer) 시절 자산이 남아 있다. GR00T 파이프라인에서는 쓰지 않으나 일부러 지우지 않았다.

- `scripts/act/`, `scripts/imitation_learning/act/`
- `source/.../OMY/elevator_call/` (구버전 task)
- `checkpoints/` 내 ACT 체크포인트 (~376MB)

ACT 결과를 재현해야 할 일이 생기면 이쪽을 본다. 필요 없다고 판단되면 그때 정리해도 된다.

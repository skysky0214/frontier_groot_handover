# Frontier-GR00T 엘리베이터 누르기 인수인계

이 레포 자체엔 코드가 없다. clone 하고 `./setup.sh` 만 돌리면 작업이 흩어져 있던 세 레포가
알맞은 브랜치로 받아져서 환경이 복원된다.

## 뭐 하던 작업인지

ROBOTIS 의 **Frontier** 로봇(바퀴 달린 모바일 베이스 위에 OMY 6축 로봇팔이 얹힌 형태)이
실내에서 엘리베이터 호출 버튼을 정확히 누르는 동작을 학습시키는 작업이다. 학습 모델은
NVIDIA 의 **GR00T VLA**(Vision-Language-Action 모델, N1.6 릴리스)를 우리 데이터로
fine-tune 한다.

전 과정이 Isaac Sim 시뮬레이션 안에서 닫혀 있다. 즉:

1. 시뮬에서 IK 기반 teacher 스크립트로 데모를 자동 수집
2. 수집된 HDF5 를 LeRobot v2.1 데이터셋 포맷으로 변환
3. GR00T 를 그 데이터셋으로 fine-tune
4. 시뮬을 다시 띄워서 학습된 정책으로 추론·평가

실기 로봇으로는 아직 안 옮겼다. 추론은 한 프로세스가 아니라 세 프로세스가 협업한다 —
GR00T 모델 서버, 시뮬과 서버를 잇는 Zenoh 브리지(DDS pub/sub 기반 통신), Isaac Sim 환경
자체. 셋 다 떠 있어야 한 스텝이 돈다.

## 빠르게 시작

```bash
git clone git@github.com:skysky0214/frontier_groot_handover.git
cd frontier_groot_handover
./setup.sh
```

`setup.sh` 가 아래 세 레포를 `repos/` 아래 받아 알맞은 브랜치로 체크아웃한다. 그 다음
DataCrunch NFS 마운트, 컨테이너 기동, 4단계 파이프라인 순으로 진행하면 된다. 환경 셋업
디테일은 뒤에.

## 코드 위치 (세 레포)

코드가 세 레포로 나뉘어 있는데, 의도가 있다. 각각 다른 upstream 을 따라가야 해서 한 곳에
모을 수 없었다.

**`skysky0214/Isaac-GR00T` — GR00T 모델 코드 (브랜치 `frontier_groot`)**

NVIDIA 가 공개한 [Isaac-GR00T](https://github.com/NVIDIA/Isaac-GR00T) 의 fork. `n1.6-release`
태그 위에 5 커밋만 얹은 가벼운 변경. 추가한 건 학습 옵션 하나(`view_dropout` — 학습 중
일부 카메라 view 를 무작위로 dropout 해서 특정 카메라에 과의존하지 않게 함), TensorRT
엔진 경로 옵션, 모델 forward 의 timing 로깅, OMY 로봇용 모달리티 config 예시 폴더.

**`skysky0214/elevator_button_press_task` — Isaac Sim 환경·운영 코드 (브랜치 `frontier_groot`)**

ROBOTIS 가 공개한 [robotis_lab](https://github.com/ROBOTIS-GIT/robotis_lab) 의 fork. 이름이
좀 안 맞는 건 이 fork 가 원래 ACT(Action Chunking Transformer) 모방학습 시절 그 task 만
신경 쓰고 떴던 이름이기 때문이다. 내용물은 robotis_lab 전체 트리 그대로. 우리가 GR00T 용
으로 추가·수정한 것:

- `source/.../assets/robots/Frontier.py` — Frontier 로봇 자산 정의 (USD 경로, 관절 한계,
  액추에이터 등)
- `source/.../OMY/elevator_call_v2_aux/` — GR00T 학습용 Isaac Lab task 정의. 기존
  `elevator_call/` 에 보조 관측(버튼이 카메라에 찍힌 픽셀 좌표 등)을 더한 버전이라
  이름이 `_v2_aux`
- `scripts/data_conversion/hdf5_to_v1.py` — 수집된 HDF5 를 LeRobot v2.1 로 변환
- `scripts/sim2real/imitation_learning/inference/inference_demos.py` + 같은 디렉토리의
  `inference_helpers/` 패키지 — Isaac Sim 환경을 띄우고 학습된 정책을 돌려보는 평가
  스크립트. 원래 1800줄짜리 한 파일이었는데 main 함수를 7개 helper 모듈(`viz`, `dump`,
  `ik_fallback`, `elevator_5floor`, `collision`, `env_setup`, `frontier_setup`)로 쪼개서
  지금은 888줄
- `configs/modality/omy_config.py` 등 — GR00T 모달리티 정의 (어떤 카메라 3개, 어떤 state,
  어떤 action 차원)

**`ROBOTIS-move/frontier_simulation` — 회사 내부 시뮬 인프라 (두 브랜치)**

ROBOTIS-move org 의 내부 레포라 같은 조직 멤버여야 접근 가능. 두 브랜치를 쓴다.

- `feature-frontier-teacher` — 데모 수집 teacher 스크립트(PR #15). 처음엔 한 파일짜리
  monolith 였는데 모듈화된 형태로 정리. 진입점 `script/isaac_sim/example/diffik_teacher_jointpos_frontier.py`
  + `frontier_helpers/` 패키지 (`ik.py`, `elevator.py`, `cam_overrides.py`, `collision.py`).
- `feature-zenoh-inference-groot` — 추론 시 시뮬과 모델 서버 사이를 잇는 Zenoh 브리지,
  그리고 학습·평가에 쓰는 5층 엘리베이터 USD 자산. `script/isaac_sim/zenoh/zenoh_inference.py`,
  `policies/groot_policy.py`, `source/isaac_sim/assets/elevator/5_floor.usd`.

robotis_lab fork 안에는 ACT 모방학습 시절(이 fork 의 초기 작업)에 만들어둔 자산이 그대로
남아 있다 — 옛 teacher 두 개, 옛 task 정의(`elevator_call/`), ACT 로 학습한 체크포인트
약 376MB. GR00T 파이프라인은 안 쓰지만 일부러 안 지웠다. ACT 시절 결과를 재현해야 할 때를
대비.

## 데이터·체크포인트는 NFS 에

학습 데이터, 변환본, 체크포인트는 git 에 안 들어가고 별도의 NFS 볼륨에 있다. DataCrunch
(GPU 클라우드 제공자) 가 호스팅하는 `nfs.fin-03.datacrunch.io:/Dataset-789fd28b` 를 호스트와
컨테이너 양쪽에서 `/mnt/Dataset` 으로 마운트한다. 480GB 짜리고, VM 인스턴스가 바뀌어도 NFS
는 살아남으니 IP 가 바뀌어도 다시 마운트만 하면 자료가 그대로 있다.

볼륨 안 구조는 대략 이렇다:

- `frontier_*` — 수집된 raw HDF5 데모들. 각 폴더가 한 번의 수집 run.
- `evButtonPush_*_v1/` — 위를 LeRobot v2.1 로 변환한 것들. 학습 입력.
- `Isaac-GR00T/` — 학습이 실제로 돌아가는 GR00T working tree. fork 와 별도 사본이라 변경
  시 sync 필요 (fork 가 진실의 출처).
- `gr00t_configs/` — 학습이 실제로 읽는 모달리티 config 사본. 이것도 fork 의
  `configs/modality/` 와 별도 사본.
- `checkpoints_*` — fine-tune 결과 체크포인트들. 각 폴더 안에 step 단위 ckpt 들.
- `trt_*` — TensorRT 로 변환된 가속 엔진들. Blackwell 계열 GPU 전용이라 다른 GPU 에선 다시
  빌드해야 한다 (`Isaac-GR00T/scripts/deployment/build_tensorrt_engine.py`).

NFS 용량이 빠듯하다. 480GB 중 보통 20-30GB 정도만 남아 있어서, 새 체크포인트 저장 전
`df -h /mnt/Dataset` 한 번씩 보고 정리해야 한다. 한 번 학습 도중에 NFS 가 꽉 차서 중간
체크포인트가 빈 파일로 저장된 적이 있어서 그 뒤로 조심.

## 한 사이클 돌리는 법

`<...>` 부분은 본인 환경에 맞게 채워 넣는 자리.

### 1. 데모 수집

```bash
# frontier_simulation 의 teacher 사용 (PR #15)
python script/isaac_sim/example/diffik_teacher_jointpos_frontier.py \
  --N 40 \
  --robot-lateral-jitter 0.05 --robot-depth-jitter 0.05 \
  --out /mnt/Dataset/<run-name>/
```

5단계 trajectory (approach → press → hold → retract → home) 로 N 개 에피소드 자동 생성.
출력은 HDF5. `--robot-*-jitter` 로 로봇 초기 위치를 무작위화 — 데이터 다양성 확보.

### 2. LeRobot v2.1 로 변환

```bash
# robotis_lab fork
python scripts/data_conversion/hdf5_to_v1.py \
  --in  /mnt/Dataset/<run-name>/ \
  --out /mnt/Dataset/<dataset-name>_v1/
```

float32 강제, `modality.json` 작성, 영상 재인코딩까지 한꺼번에.

### 3. fine-tune

```bash
# Isaac-GR00T fork 안에서
python gr00t/experiment/launch_finetune.py \
  --dataset_path /mnt/Dataset/<dataset-name>_v1/ \
  --output_dir   /mnt/Dataset/checkpoints_<run-name>/ \
  --max_steps 2000 \
  --view_dropout 0.3
```

`view_dropout` 은 우리가 추가한 옵션. 학습 중 일부 카메라 view 를 무작위로 가려서 모델이
한 카메라에 과의존하지 않게 한다.

### 4. 추론 (3 프로세스, 순서 중요)

같은 컨테이너 안에서 셸 셋으로 띄운다. A → B → C 순서.

```bash
# A. GR00T 모델 서버 (ZMQ REP socket)
python gr00t/eval/run_gr00t_server.py \
  --ckpt /mnt/Dataset/checkpoints_<run-name>/<ckpt-step>/ \
  --modality examples/omy_callbutton/omy_config.py
# 학습된 ckpt 가 Blackwell GPU 용 TRT 엔진으로 변환돼 있다면:
#   --trt_engine_path /mnt/Dataset/trt_<run>/dit_model_bf16.trt

# B. Zenoh 브리지 (시뮬 ↔ 서버 중계)
python script/isaac_sim/zenoh/zenoh_inference.py --policy groot --use_frontier

# C. Isaac Sim 환경 + 자동 평가
python scripts/sim2real/imitation_learning/inference/inference_demos.py \
  --auto_eval --dump_inference
```

B 없이 C 만 띄우면 `inference_demos` 가 첫 `env.step` 도 못 들어간다. 침묵 실패(에러 없이
그냥 안 진행)라 한참 헤맬 수 있다 — 디버깅하느라 시간 많이 썼던 적 있다.

### 추론 속도 참고

GR00T 모델 forward 와 시뮬 step 이 별개로 도는 비동기 구조라, 정책이 한 번 추론을 돌리면
여러 step 분량의 action chunk 를 받아 와서 그걸 풀며 시뮬을 진행한다. `chunk_len` 이
trade-off 의 핵심: 크면 모델 호출 빈도가 줄어 부드러운데 reactive 가 떨어지고, 작으면
reactive 한데 GPU 가 자주 깨어난다.

대략적인 측정값 (Blackwell GPU 1장 기준):

- 모델 forward: ~170ms (BF16, diffusion 4 step)
- 시뮬 step: ~72ms
- chunk_len=16 이면 한 사이클이 약 1.15초 → 실효 replan rate 0.87Hz
- chunk_len=3 까지 줄이면 4.6Hz, GPU 활용률 78% (sweet spot)

자세한 표와 데이터 흐름 다이어그램은 `/home/ub/cosmos_run12/groot_inference_pkg/README.md`
에 정리해뒀다.

## 환경

DataCrunch 의 GPU 인스턴스에서 작업했다. VM IP 가 자주 바뀌니까 `~/.ssh/config` 에 alias
(`Gaemi_1`) 로 관리해두면 편하다. SSH 키는 GitHub `skysky0214` 계정과 묶여 있어서 그쪽
fork 들로의 push 가 키 인증으로 바로 된다.

```bash
# NFS 마운트 (호스트에서 먼저)
sudo mkdir -p /mnt/Dataset
sudo mount -t nfs -o nconnect=16 nfs.fin-03.datacrunch.io:/Dataset-789fd28b /mnt/Dataset

# 컨테이너 기동 (이미지 isaac-sim-custom:5.1.0)
docker start isaac-sim
```

NFS 가 호스트에 마운트된 다음 컨테이너를 켜야 컨테이너 안에서 `/mnt/Dataset` 이 보인다.
순서 거꾸로 가면 컨테이너 재시작.

GPU 는 **RTX PRO 6000 Blackwell (SM 12.0)** 정도면 잘 돈다. **B300 (SM 10.3) 은 피할 것** —
Isaac Sim 의 bundled CUDA 12.8 nvrtc 가 SM 10.3 을 지원 안 한다. `TORCH_CUDA_ARCH_LIST` 도,
`PYTORCH_JIT=0` 도 우회가 안 됐다. DataCrunch 에서 VM 잡을 때 GPU 모델 꼭 확인.

학습에 쓰는 DeepSpeed 가 빌드 시 `nvcc` 를 찾는데 컨테이너에 nvcc 가 없다. fake shim 을
만들어주면 우회된다 (컨테이너 재시작 시 사라지니 다시 만들기):

```bash
mkdir -p /tmp/fake_cuda/bin
echo '#!/bin/bash' > /tmp/fake_cuda/bin/nvcc
chmod +x /tmp/fake_cuda/bin/nvcc
export PATH=/tmp/fake_cuda/bin:$PATH
```

## 어디까지 했는지

학습은 데이터 변형(스폰 jitter 범위·LED 처리 차이 등) 별로 여러 변종을 만들어 비교
중이었다. 각 데이터셋에 대해 `/mnt/Dataset/checkpoints_<variant>/` 아래에 fine-tune 결과가
들어 있고, 그 안에 step 단위 ckpt 들이 쌓여 있다. 일부 데이터셋들을 합친 combined 학습이
진행 중이었고 그건 아직 미완. TensorRT 변환은 가장 안정적인 ckpt 하나로 한 번 빌드해서
동작 확인.

코드 쪽 정리는 끝났다 — 절대 경로는 환경변수로 빼서 다른 머신에서도 동작하게 하고,
`inference_demos.py` 모듈화 끝내고, 운영 로그는 `_log` wrapper 로 묶어서 `VERBOSE=0` 으로
입막음 가능하게 했다.

남은 후보:

- Combined 학습 마저 끝내고 평가
- 진짜 가치 있는 ckpt 와 데이터셋은 HuggingFace Hub 으로 옮기는 게 안전 (지금은 NFS 사본만
  존재. 인스턴스가 죽으면 NFS 도 같이 위태로워질 수 있음)
- 실기 로봇 이식 검토 — 지금까지는 전부 시뮬. sim2real gap, latency, contact 처리 등 검증
  필요

## 처음 보면 헷갈릴 만한 것들

**fork 이름이 일관성 없다.** robotis_lab fork 의 이름이 `elevator_button_press_task`. ACT
시절에 그 task 만 신경 써서 그렇게 지었던 게 그대로 남았다. 안 내용물은 robotis_lab 전체.

**같은 파일이 두 군데 있을 수 있다.** 모달리티 config 와 Isaac-GR00T 코드가 그렇다 — fork
에 한 사본, NFS 의 working tree 에 한 사본. 학습 스크립트는 NFS 사본을 읽는다. fork 가
진실의 출처 (소스 컨트롤 받음). 변경 시 둘 다 sync 해야 학습에 반영된다.

**OMY task 가 두 가지가 같이 있다.** `source/.../OMY/` 폴더에 `elevator_call/` 과
`elevator_call_v2_aux/` 가 공존한다. GR00T 파이프라인은 무조건 `_v2_aux` 쪽 (gym ID 에
`-Aux-` 가 붙은 것들). 구버전은 ACT 시절 결과 재현용으로 남겨뒀다.

**3-프로세스 추론은 순서가 있다.** A(server) → B(zenoh) → C(inference_demos). B 안 띄우면
C 가 침묵 실패한다. 에러 메시지가 거의 없어서 한참 모를 수 있다.

**ACT 시절 자산이 fork 안에 살아 있다.** `scripts/act/`, `scripts/imitation_learning/act/`,
`task/`, `source/.../OMY/elevator_call/`, `checkpoints/` (체크포인트만 376MB). GR00T 는
안 쓰지만 일부러 안 지웠다. 필요 없다고 판단되면 따로 정리.

## 알아두면 도움 되는 함정들

NFS 가 학습 도중 꽉 차면 그 시점 ckpt 가 빈 파일로 저장된다. 저장 전 `df` 한 번씩.

`docker commit` 이 한 번 깨진 적 있다 — containerd image layer digest 가 손상돼서. 우회는
`docker export` 로 했다 (live FS 를 읽으니 image store 안 거치고 빠져나옴).

`.gitignore` 에 `*.usd` 가 들어 있어서 fork 에 USD 추가하려면 `git add -f`. 5층 엘리베이터
USD (58KB) 가 그렇게 들어갔다 — 작아서 LFS 안 썼다.

컨테이너 안에 git 이 안 깔려 있다. git 작업은 호스트에서.

DataCrunch VM 이 바뀌면 같은 IP 에 다른 호스트 키가 들러붙어서 SSH 가 거부할 때가 있다.
`ssh-keygen -R <ip>` 후 재접속.

`elevator_button_press_task` 를 clone 하면 `data/object/*.usd` 16개에 대해 "should have
been pointers but weren't" LFS 경고가 뜬다. 우리 변경 아니고 옛 작업물 — 그 USD 들을 실제
쓸 일 있으면 LFS 정리가 필요하지만 GR00T 파이프라인엔 영향 없다.

---

추론 파이프라인을 코드 수준에서 더 자세히 보고 싶으면
`/home/ub/cosmos_run12/groot_inference_pkg/README.md` 에 timing 표, chunk_len trade-off,
데이터 흐름 다이어그램이 정리돼 있다.

# Mass AI 시스템 개요

> **문서 목적**: Mass AI의 기본 개념과 전통적 Actor 기반 AI와의 차이점 이해
>
> **대상 독자**: 블루프린트 개발자부터 C++ 개발자까지

---

## 1. Mass AI란? - 쉽게 이해하기

### 한 줄 요약
**Mass AI는 "수천 마리의 몬스터를 60fps로 돌리기 위한 에픽게임즈의 해결책"입니다.**

### 왜 필요한가요?

게임 개발을 하다 보면 이런 상황을 만나게 됩니다:

```
상황: 뱀파이어 서바이벌 스타일 게임을 만들고 싶어요!
문제: Actor 기반으로 몬스터 1000마리를 스폰하면...
결과: 프레임이 10fps로 떨어집니다 😱
```

**블루프린트에서 Spawn Actor를 1000번 호출하면 어떻게 될까요?**

- 각 Actor마다 ~2KB 이상의 메모리가 필요해요
- 매 프레임마다 1000개의 Tick 함수가 개별적으로 호출돼요
- 렌더링도 각각 따로 처리되어 Draw Call이 폭발해요

Mass AI는 이 문제를 근본적으로 해결합니다. **같은 1000마리를 훨씬 적은 비용으로 처리**할 수 있거든요.

---

## 2. "데이터 지향 설계"가 뭔가요?

### 전통적 방식 (객체 지향) vs Mass AI (데이터 지향)

**비유로 이해하기: 학교 급식 배식**

**객체 지향 방식** (Actor 기반):
```
👨‍🍳 "1번 학생 나와서 밥 받아가세요"
👨‍🍳 "2번 학생 나와서 밥 받아가세요"
👨‍🍳 "3번 학생 나와서 밥 받아가세요"
...
👨‍🍳 "1000번 학생 나와서 밥 받아가세요"

결과: 1000번의 개별 서빙 -> 시간이 오래 걸림
```

**데이터 지향 방식** (Mass AI):
```
👨‍🍳 "밥 담당: 1000명분 밥 한 번에 퍼서 줄 세워서 전달"
👨‍🍳 "국 담당: 1000명분 국 한 번에 퍼서 줄 세워서 전달"
👨‍🍳 "반찬 담당: 1000명분 반찬 한 번에 나눠서 전달"

결과: 같은 종류 작업을 한 번에 처리 -> 훨씬 빠름!
```

### 코드로 보는 차이

**블루프린트/Actor 방식** (익숙한 방식):
```cpp
// 각 몬스터 Actor가 자기 일을 개별적으로 처리
void AMonster::Tick(float DeltaTime)
{
    // 1. 플레이어 위치 찾기
    // 2. 방향 계산
    // 3. 이동
    // 4. 공격 체크
    // 5. 애니메이션 업데이트
}
// 이게 1000번 반복됨 = 1000번의 함수 호출 오버헤드
```

**Mass AI 방식**:
```cpp
// 이동 전담 Processor가 모든 몬스터를 한 번에 처리
void UMovementProcessor::Execute(...)
{
    // 1000마리의 위치를 한 번에 업데이트
    for (int i = 0; i < 1000; i++)
    {
        Positions[i] += Velocities[i] * DeltaTime;
    }
}
// 1번의 함수 호출로 1000마리 처리!
```

---

## 3. ECS 패턴 - 세 가지 핵심 개념

Mass AI는 **Entity-Component-System (ECS)** 패턴을 사용합니다. 이름이 어려워 보이지만, 개념은 간단해요!

### Entity (엔티티) = "이름표"

**블루프린트 비유**: `Spawn Actor`로 만들어진 Actor 레퍼런스 같은 거예요.

```
Entity는 그냥 "이 몬스터는 몇 번이야"라는 식별 번호일 뿐이에요.
데이터를 직접 가지고 있지 않아요.

Entity #1 → "나는 1번 몬스터"
Entity #2 → "나는 2번 몬스터"
Entity #3 → "나는 3번 몬스터"
```

코드에서는 `FMassEntityHandle`로 표현됩니다.

### Fragment (프래그먼트) = "데이터 카드"

**블루프린트 비유**: Actor에 붙이는 Component의 변수들과 비슷해요. 하지만 **함수 없이 데이터만** 있어요.

```cpp
// Transform Fragment - 위치, 회전, 스케일 정보
struct FTransformFragment : FMassFragment
{
    FTransform Transform;  // 이것만 있음! 함수 없음!
};

// Velocity Fragment - 속도 정보
struct FMassVelocityFragment : FMassFragment
{
    FVector Value;  // 속도 벡터만!
};

// Health Fragment - 체력 정보
struct FHealthFragment : FMassFragment
{
    float CurrentHealth;
    float MaxHealth;
};
```

**왜 데이터만 분리하나요?**
- 같은 종류의 데이터가 메모리에 연속으로 배치됨
- CPU가 한 번에 읽어서 처리하기 좋음
- 캐시 효율성이 극대화됨

### Processor (프로세서) = "일꾼"

**블루프린트 비유**: Tick 이벤트에서 하던 모든 로직을 담당하는데, **모든 Entity를 한꺼번에 처리**해요.

```cpp
// 이동 처리 전담 Processor
class UMovementProcessor : public UMassProcessor
{
    void Execute(...) override
    {
        // "이동이 필요한 모든 몬스터를 한 번에 처리할게요!"
        Query.ForEachEntityChunk([](FMassExecutionContext& Context)
        {
            // 위치 데이터 배열
            auto Positions = Context.GetMutableFragmentView<FTransformFragment>();
            // 속도 데이터 배열
            auto Velocities = Context.GetFragmentView<FMassVelocityFragment>();

            // 한 번에 쭉 처리
            for (int i = 0; i < Context.GetNumEntities(); ++i)
            {
                Positions[i].Transform.AddToTranslation(
                    Velocities[i].Value * Context.GetDeltaTimeSeconds()
                );
            }
        });
    }
};
```

### 세 가지가 어떻게 연결되나요?

```
┌─────────────────────────────────────────────────────────────────┐
│                        전체 흐름                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ① Entity Manager가 Entity들을 관리                             │
│     "1번~1000번 몬스터가 있어요"                                 │
│                                                                  │
│  ② 각 Entity는 여러 Fragment를 "참조"                           │
│     Entity 1 → [Transform] [Velocity] [Health]                  │
│     Entity 2 → [Transform] [Velocity] [Health]                  │
│     ...                                                          │
│                                                                  │
│  ③ Processor들이 순서대로 Fragment를 처리                        │
│     Movement Processor: 모든 [Transform]과 [Velocity] 처리      │
│     Combat Processor: 모든 [Health] 처리                        │
│     Render Processor: 모든 [Transform]과 [Visual] 처리          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. 왜 이렇게 빨라지나요? - 성능 원리

### CPU 캐시 이해하기

컴퓨터에서 가장 빠른 메모리는 **CPU 캐시**예요. 문제는 크기가 작다는 거죠.

```
속도 비교:
CPU 레지스터: 1 사이클 (가장 빠름)
L1 캐시: ~4 사이클
L2 캐시: ~12 사이클
L3 캐시: ~40 사이클
메인 메모리(RAM): ~200 사이클 (가장 느림!)
```

**Actor 방식의 문제**:
```
메모리 상태:
[Actor1의 모든 데이터] ... [빈 공간] ... [Actor2의 모든 데이터] ... [빈 공간] ...

Actor1의 위치 읽기 → 캐시에 Actor1 전체 로드 (불필요한 것도 다 포함)
Actor2의 위치 읽기 → 캐시 미스! 메모리에서 다시 로드 (200 사이클 손해)
Actor3의 위치 읽기 → 캐시 미스! 또 메모리에서 로드...

결과: 캐시 히트율 30~50%
```

**Mass AI 방식의 장점**:
```
메모리 상태:
위치 배열: [Pos1][Pos2][Pos3][Pos4][Pos5]... (연속!)
속도 배열: [Vel1][Vel2][Vel3][Vel4][Vel5]... (연속!)

Pos1 읽기 → 캐시에 [Pos1~Pos16] 한 번에 로드
Pos2 읽기 → 이미 캐시에 있음! (1 사이클)
Pos3 읽기 → 이미 캐시에 있음! (1 사이클)
...

결과: 캐시 히트율 90% 이상!
```

### 실제 성능 비교

| 항목 | Actor 기반 | Mass AI | 개선율 |
|------|------------|---------|--------|
| **엔티티당 메모리** | ~2KB+ | ~100B | **20배 감소** |
| **Tick 호출 오버헤드** | 1000번 개별 호출 | 1번 배치 호출 | **1000배 감소** |
| **캐시 효율성** | 30-50% | 90%+ | **2배 이상** |
| **드로우 콜** | 1000번 | ISM 1~10번 | **100배 감소** |
| **동시 처리 가능** | 수백 개 | 수천~수만 개 | **100배 증가** |

---

## 5. 그래서 언제 Mass AI를 써야 하나요?

### Mass AI가 딱 맞는 경우

| 게임 장르/상황 | 왜 적합한가요? |
|----------------|----------------|
| **뱀파이어 서바이벌** | 수천 마리 몬스터가 단순한 행동(추적, 접촉 공격)만 함 |
| **군중 시뮬레이션** | NPC들이 비슷한 패턴으로 움직임 |
| **RTS 유닛** | 수백 유닛이 비슷한 로직으로 이동/전투 |
| **탄막 슈팅** | 수천 발사체가 간단한 궤적으로 이동 |
| **물고기 떼, 새 떼** | 군집 행동이 필요한 대량 엔티티 |

### Actor를 그대로 쓰는 게 나은 경우

| 상황 | 왜 Actor가 나은가요? |
|------|----------------------|
| **플레이어 캐릭터** | 개별 처리가 필요하고, 복잡한 상호작용 많음 |
| **보스 몬스터** | 복잡한 AI 상태 기계, 개별 연출 필요 |
| **복잡한 물리 상호작용** | 엔진의 Physics 시스템 직접 사용 필요 |
| **소수의 중요한 NPC** | 대화, 퀘스트 등 복잡한 개별 로직 |

### 실전 조언

```
"내 게임에 Mass AI가 필요할까?"

질문 1: 동시에 화면에 몇 개의 AI가 필요한가요?
  - 100개 이하 → Actor로 충분
  - 100~500개 → 최적화된 Actor 또는 Mass AI 검토
  - 500개 이상 → Mass AI 강력 추천

질문 2: AI의 행동이 얼마나 복잡한가요?
  - 단순 (추적, 도망, 순찰) → Mass AI 적합
  - 복잡 (대화, 퀘스트, 복잡한 전투) → Actor 유지

질문 3: 이미 만든 AI 로직이 많나요?
  - 새로 시작 → Mass AI로 설계 권장
  - 기존 Actor AI 많음 → 하이브리드 접근 (가까운 것만 Actor)
```

---

## 6. Mass AI 시작하기 - 플러그인 활성화

### 방법 1: 프로젝트 설정에서 활성화

1. 언리얼 에디터 열기
2. **Edit → Plugins** 메뉴 클릭
3. 검색창에 "Mass" 입력
4. 다음 플러그인들 체크:
   - **MassEntity** (핵심)
   - **MassGameplay** (게임플레이 기능)
   - **MassAI** (AI 행동)
5. "Mass" 대신 "StateTree" 검색
6. 다음 플러그인 체크:
   - **StateTree** (상태 기계)
   - **GameplayStateTree** (게임플레이 통합)
7. 에디터 재시작

### 방법 2: .uproject 파일 직접 수정

```json
{
  "Plugins": [
    { "Name": "MassEntity", "Enabled": true },
    { "Name": "MassGameplay", "Enabled": true },
    { "Name": "MassAI", "Enabled": true },
    { "Name": "StateTree", "Enabled": true },
    { "Name": "GameplayStateTree", "Enabled": true }
  ]
}
```

### C++ 프로젝트의 경우 - Build.cs 설정

```csharp
// YourProject.Build.cs
PublicDependencyModuleNames.AddRange(new string[]
{
    // Mass AI 핵심
    "MassEntity",
    "MassCommon",

    // 게임플레이 기능
    "MassSpawner",         // 대량 스폰
    "MassRepresentation",  // 렌더링 (ISM, Actor)
    "MassLOD",             // LOD 관리
    "MassMovement",        // 이동
    "MassSignals",         // 이벤트 통신
    "MassActors",          // Actor 통합

    // AI 행동
    "MassAIBehavior",      // AI 행동
    "StateTreeModule",     // StateTree 기본
    "GameplayStateTreeModule"  // 게임플레이 StateTree
});
```

---

## 7. 핵심 클래스 한눈에 보기

### 알아야 할 핵심 클래스들

| 클래스 | 블루프린트 비유 | 역할 |
|--------|-----------------|------|
| `FMassEntityManager` | World의 Actor 관리자 | 모든 Entity 생성/삭제/관리 |
| `FMassEntityHandle` | Actor 레퍼런스 | Entity 식별 핸들 |
| `FMassFragment` | Component의 변수들 | 순수 데이터 구조체 |
| `UMassProcessor` | Tick 함수 | 로직 처리 담당 |
| `FMassEntityQuery` | GetAllActorsOfClass | Entity 검색/필터링 |
| `UMassEntityConfigAsset` | Actor Blueprint | Entity 구성 정의 |
| `AMassSpawner` | Spawn Actor 노드 | 대량 Entity 스폰 |

### MassGameplay 주요 모듈

| 모듈 | 하는 일 | 언제 쓰나요? |
|------|---------|--------------|
| **MassSpawner** | 대량 스폰 | 몬스터 웨이브 생성 |
| **MassRepresentation** | 시각적 표현 | ISM/Actor 렌더링 |
| **MassLOD** | LOD 관리 | 거리별 최적화 |
| **MassMovement** | 이동 처리 | 몬스터 이동 |
| **MassSignals** | 이벤트 통신 | 피격, 사망 등 이벤트 |
| **MassSmartObjects** | 상호작용 | 아이템 줍기 등 |
| **MassActors** | Actor 통합 | 기존 Actor와 연결 |

---

## 8. 다음 단계

Mass AI의 기본 개념을 이해했다면, 다음 문서에서 코어 아키텍처를 상세히 살펴보겠습니다:

- **다음**: [02_CoreArchitecture.md](02_CoreArchitecture.md) - Entity, Fragment, Processor, Archetype 시스템 상세 분석

### 추천 학습 순서

1. ✅ **01_SystemOverview** (현재) - 기본 개념 이해
2. ⬜ **02_CoreArchitecture** - 핵심 구조 파악
3. ⬜ **05_BehaviorLogic** - 행동 로직 (StateTree 포함)
4. ⬜ **03_RenderingAndLOD** - 렌더링 최적화
5. ⬜ **04_AnimationIntegration** - 애니메이션 통합
6. ⬜ **06_AbilitySystemIntegration** - GAS 통합 방법
7. ⬜ **07_OptimizationGuide** - 실전 최적화
8. ⬜ **08_StateTreeGuide** - StateTree 완전 가이드
9. ⬜ **09_QuickStartTutorial** - 따라하기 튜토리얼

# Mass AI 프레임워크 분석 리포트

> **언리얼 엔진 5.7 Mass AI 시스템 스터디 문서**
>
> 작성일: 2025-12-29
> 최종 업데이트: 2025-12-29 (v2 - 구어체 스타일 업그레이드)
>
> 목표: 뱀파이어 서바이벌 스타일의 대량 몬스터 시스템 구현을 위한 인사이트 제공

---

## 문서 목록

### 핵심 문서

| 번호 | 문서명 | 설명 | 난이도 |
|------|--------|------|--------|
| 01 | [SystemOverview](01_SystemOverview.md) | Mass AI가 뭔가요? 왜 써야 하나요? | ★☆☆☆☆ |
| 02 | [CoreArchitecture](02_CoreArchitecture.md) | Entity, Fragment, Processor 상세 분석 | ★★★☆☆ |
| 03 | [RenderingAndLOD](03_RenderingAndLOD.md) | ISM 렌더링과 LOD 시스템 | ★★★☆☆ |
| 04 | [AnimationIntegration](04_AnimationIntegration.md) | AnimBP 연동, Translator 시스템 | ★★★★☆ |
| 05 | [BehaviorLogic](05_BehaviorLogic.md) | StateTree, Signal, Processor 행동 | ★★★★☆ |
| 06 | [AbilitySystemIntegration](06_AbilitySystemIntegration.md) | GAS 하이브리드 통합 전략 | ★★★★☆ |
| 07 | [OptimizationGuide](07_OptimizationGuide.md) | 프로파일링과 최적화 실전 가이드 | ★★★★☆ |

### 심화 문서

| 번호 | 문서명 | 설명 | 난이도 |
|------|--------|------|--------|
| 08 | [StateTreeGuide](08_StateTreeGuide.md) | StateTree 완전 가이드 (Mass 통합) | ★★★☆☆ |
| 09 | [QuickStartTutorial](09_QuickStartTutorial.md) | 10분 만에 1000마리 스폰하기 | ★★☆☆☆ |
| 10 | [InstancedSkeletalMeshAnalysis](10_InstancedSkeletalMeshAnalysis.md) | Instanced Skeletal Mesh + Mass AI 통합 분석 | ★★★★☆ |

---

## 핵심 요약

### Mass AI가 뭔가요?

**한 줄 요약**: "수천 마리 AI를 60fps로 돌리는 마법"

Mass AI는 **데이터 지향 설계 (DOD)** 기반 AI 프레임워크예요.
전통적인 Actor 기반 AI와 달리, **Entity Component System (ECS)** 패턴을 사용합니다.

### 왜 Mass AI인가?

```
                전통적 Actor AI          vs          Mass AI
                ─────────────                        ──────────

엔티티당 비용:    ~2KB+ (AActor)                      ~100B (Fragment)
처리 방식:        개별 Tick()                         배치 Processor
캐시 효율:        낮음 (데이터 분산)                   높음 (연속 메모리)
렌더링:           개별 Draw Call                      ISM 배치
확장성:           수백 개 한계                        수만 개 가능!

결과: 같은 하드웨어로 10-20배 더 많은 AI 처리 가능
```

### 1000-5000 마리 권장 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                        플레이어 기준 거리                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌─────────────┐   ┌─────────────┐   ┌─────────────────────┐   │
│   │  High LOD   │   │ Medium LOD  │   │      Low LOD        │   │
│   │   (0-50m)   │   │  (50-200m)  │   │      (200m+)        │   │
│   ├─────────────┤   ├─────────────┤   ├─────────────────────┤   │
│   │   50-100개  │   │   ~500개    │   │     나머지 전부     │   │
│   │             │   │             │   │                     │   │
│   │  - Actor    │   │  - LowActor │   │  - ISM 렌더링       │   │
│   │  - 풀 애니  │   │  - 간소화   │   │  - 애니 없음        │   │
│   │  - GAS OK   │   │  - Fragment │   │  - 최소 로직        │   │
│   └─────────────┘   └─────────────┘   └─────────────────────┘   │
│                                                                  │
│   CPU: ~3ms        CPU: ~1ms           CPU: ~0.5ms              │
│   GPU: 100 DC      GPU: 10 DC          GPU: 1 DC                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 읽기 순서 가이드

### 처음 시작하는 분

```
1. 09_QuickStartTutorial.md  ← 먼저 손으로 따라해보세요!
2. 01_SystemOverview.md      ← 왜 이렇게 하는지 이해
3. 02_CoreArchitecture.md    ← 핵심 구조 파악
```

### 이미 ECS를 아시는 분

```
1. 02_CoreArchitecture.md    ← Mass Entity 특징 파악
2. 03_RenderingAndLOD.md     ← LOD 시스템 이해
3. 07_OptimizationGuide.md   ← 바로 최적화
```

### 기존 GAS 프로젝트에 도입하려는 분

```
1. 06_AbilitySystemIntegration.md  ← 하이브리드 전략
2. 03_RenderingAndLOD.md           ← LOD별 GAS 활성화
3. 04_AnimationIntegration.md      ← Actor-Entity 동기화
```

### 복잡한 AI 행동이 필요한 분

```
1. 05_BehaviorLogic.md     ← 행동 시스템 전반
2. 08_StateTreeGuide.md    ← StateTree 상세
3. 02_CoreArchitecture.md  ← Signal 시스템
```

---

## 핵심 개념 빠른 참조

### Entity Component System

```
전통적 OOP (Actor):
├── Monster.cpp에 모든 로직
├── 상속으로 확장
└── 개별 Tick 처리

Data-Oriented (Mass):
├── Fragment: 순수 데이터
├── Processor: 순수 로직
├── 조합으로 확장
└── 배치 처리
```

### 주요 클래스

| 클래스 | 역할 | 블루프린트 비유 |
|--------|------|----------------|
| `FMassEntityHandle` | 엔티티 ID | Actor 참조 |
| `FMassFragment` | 데이터 컨테이너 | Actor Component |
| `UMassProcessor` | 로직 처리기 | Tick 이벤트 |
| `UMassEntityTraitBase` | 템플릿 구성 | Actor Blueprint |
| `FMassEntityQuery` | 엔티티 필터링 | Get All Actors of Class |

### LOD 시스템

| LOD 레벨 | 표현 방식 | 처리 복잡도 |
|----------|----------|-------------|
| High | Actor + ASC | 풀 로직 |
| Medium | Low Actor | 중간 |
| Low | ISM | 최소 |
| Off | 없음 | 로직만 |

---

## 뱀파이어 서바이벌 스타일 구현 포인트

### 1. 대량 스폰

```cpp
UMassSpawnerSubsystem* Spawner = GetSubsystem<UMassSpawnerSubsystem>();
Spawner->SpawnEntities(MonsterConfig, SpawnTransforms);
```

### 2. 플레이어 추적

```cpp
// Processor에서 매 프레임
FVector Dir = (PlayerPos - MyPos).GetSafeNormal();
Movement.DesiredVelocity = Dir * ChaseSpeed;
```

### 3. 피격 처리

```cpp
// Signal로 데미지 이벤트
SignalSubsystem->SignalEntity(Entity, DamageSignal);
```

### 4. LOD 기반 GAS

```cpp
// High LOD에서만 GAS 활성화
if (LOD == EMassLOD::High)
{
    ASC->ActivateAbility(AttackAbility);
}
```

---

## 참조 소스 경로

```
엔진 코어:
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Source\Runtime\MassEntity\

MassGameplay 플러그인:
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Plugins\Runtime\MassGameplay\

StateTree 플러그인:
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Plugins\Runtime\GameplayStateTree\

MassAI 행동:
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Plugins\AI\MassAI\
```

---

## 버전 히스토리

| 버전 | 날짜 | 변경 내용 |
|------|------|----------|
| v1.0 | 2025-12-29 | 초기 문서 작성 (01-07) |
| v2.0 | 2025-12-29 | 구어체 스타일 업그레이드, 08-09 추가 |
| v3.0 | 2025-12-29 | Instanced Skeletal Mesh 분석 문서 추가 (10) |

---

**시작하기**: [09_QuickStartTutorial.md](09_QuickStartTutorial.md)로 바로 시작하세요!

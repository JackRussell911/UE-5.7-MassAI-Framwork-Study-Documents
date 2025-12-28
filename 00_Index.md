# Mass AI 프레임워크 분석 리포트

> **언리얼 엔진 5.7 Mass AI 시스템 스터디 문서**
>
> 작성일: 2025-12-29
> 목표: 뱀파이어 서바이벌 스타일의 대량 몬스터 시스템 구현을 위한 인사이트 제공

---

## 문서 목록

| 번호 | 문서명 | 설명 |
|------|--------|------|
| 01 | [SystemOverview](01_SystemOverview.md) | Mass AI 시스템 개요 및 전통적 Actor 기반 AI와의 차이점 |
| 02 | [CoreArchitecture](02_CoreArchitecture.md) | 코어 아키텍처 상세 분석 (Entity, Fragment, Processor) |
| 03 | [RenderingAndLOD](03_RenderingAndLOD.md) | 렌더링 및 LOD 시스템 분석 |
| 04 | [AnimationIntegration](04_AnimationIntegration.md) | 애니메이션 통합 전략 |
| 05 | [BehaviorLogic](05_BehaviorLogic.md) | 행동 로직 시스템 (StateTree, Signal, Smart Objects) |
| 06 | [AbilitySystemIntegration](06_AbilitySystemIntegration.md) | Gameplay Ability System 통합 분석 |
| 07 | [OptimizationGuide](07_OptimizationGuide.md) | 1000-5000 마리 규모 최적화 전략 및 구현 가이드 |

---

## 핵심 요약

### Mass AI란?
Mass AI는 언리얼 엔진 5의 **데이터 지향 설계(Data-Oriented Design)** 기반 AI 프레임워크입니다. 전통적인 Actor 기반 AI와 달리, **Entity Component System (ECS)** 패턴을 사용하여 수천 개의 AI 엔티티를 효율적으로 관리할 수 있습니다.

### 왜 Mass AI인가?

| 항목 | 전통적 Actor 기반 AI | Mass AI |
|------|----------------------|---------|
| 엔티티당 오버헤드 | AActor 풀 인스턴스 (~2KB+) | Fragment 데이터만 (~100B) |
| 틱 처리 | 개별 Tick 호출 | 배치 Processor 처리 |
| 캐시 효율성 | 낮음 (데이터 분산) | 높음 (연속 메모리 배치) |
| 렌더링 | 개별 드로우 콜 | ISM 배치 렌더링 |
| 확장성 | 수십~수백 | 수천~수만 |

### 1000-5000 마리 규모 권장 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                        Mass Entity Manager                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌─────────────┐   ┌─────────────┐   ┌─────────────────────┐   │
│   │ High LOD    │   │ Medium LOD  │   │ Low LOD             │   │
│   │ (0-50m)     │   │ (50-200m)   │   │ (200m+)             │   │
│   ├─────────────┤   ├─────────────┤   ├─────────────────────┤   │
│   │ ~50-100개   │   │ ~500개      │   │ 나머지 전부         │   │
│   │ Actor 스폰  │   │ Low Actor   │   │ ISM 렌더링          │   │
│   │ 풀 애니메이션│   │ 간소화 애니 │   │ 애니메이션 없음     │   │
│   │ GAS 활성화  │   │ 기본 로직   │   │ 최소 로직           │   │
│   └─────────────┘   └─────────────┘   └─────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 주요 참조 소스 경로

- **엔진 코어**: `C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Source\Runtime\MassEntity`
- **MassGameplay 플러그인**: `C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Plugins\Runtime\MassGameplay`
- **StateTree 플러그인**: `C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Plugins\Runtime\GameplayStateTree`

---

## 빠른 시작 가이드

### 1단계: 플러그인 활성화
프로젝트의 `.uproject` 파일에 다음 플러그인 추가:
```json
{
  "Plugins": [
    { "Name": "MassEntity", "Enabled": true },
    { "Name": "MassGameplay", "Enabled": true },
    { "Name": "StateTree", "Enabled": true },
    { "Name": "GameplayStateTree", "Enabled": true }
  ]
}
```

### 2단계: 모듈 의존성 추가
`Build.cs` 파일에 추가:
```csharp
PublicDependencyModuleNames.AddRange(new string[] {
    "MassEntity",
    "MassCommon",
    "MassMovement",
    "MassSpawner",
    "MassRepresentation",
    "MassLOD",
    "MassSignals",
    "StateTreeModule",
    "GameplayStateTreeModule"
});
```

### 3단계: 문서 순서대로 학습
1. [01_SystemOverview](01_SystemOverview.md) - 기본 개념 이해
2. [02_CoreArchitecture](02_CoreArchitecture.md) - 핵심 구조 파악
3. [05_BehaviorLogic](05_BehaviorLogic.md) - 행동 로직 구현 방법
4. [03_RenderingAndLOD](03_RenderingAndLOD.md) - 렌더링 최적화
5. [06_AbilitySystemIntegration](06_AbilitySystemIntegration.md) - GAS 통합 방법
6. [07_OptimizationGuide](07_OptimizationGuide.md) - 실전 최적화

---

## 뱀파이어 서바이벌 스타일 구현 핵심 포인트

1. **대량 스폰**: `AMassSpawner`와 `FMassEntityTemplate` 활용
2. **플레이어 추적**: 간단한 `UMassProcessor`로 방향 벡터 계산
3. **피격 처리**: Signal 시스템으로 데미지 이벤트 전파
4. **LOD 전환**: 가까운 적만 Actor로 전환하여 상세 처리
5. **GAS 통합**: High LOD 몬스터만 Ability System 활성화

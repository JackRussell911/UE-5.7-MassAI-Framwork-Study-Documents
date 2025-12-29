# Instanced Skeletal Mesh 컴포넌트 완전 가이드

> **문서 목적**: UE 5.7의 UInstancedSkinnedMeshComponent 심층 분석 및 활용 가이드
>
> **난이도**: ★★★★★ (고급)
>
> **작성일**: 2025-12-30

---

## 들어가며

### 이 문서에서 다루는 내용

```
이 문서는 Instanced Skeletal Mesh를 깊이 파헤칩니다:

├── AnimBank 시스템: 애니메이션을 어떻게 "굽는지"
├── TransformProvider: 본 데이터를 어떻게 제공하는지
├── 인스턴스 관리: ID 시스템과 변경 추적
├── 커스텀 데이터: 머티리얼 파라미터 제어
├── GPU-Only 인스턴스: 초대량 렌더링
├── 컬링 시스템: 성능 최적화
├── Nanite 통합: 차세대 렌더링
├── HLOD 활용: 월드 파티션과의 통합
└── 실전 활용: 몬스터, 군중 렌더링

⚠️ 주의: 이 기능은 UE 5.6부터 도입된 실험적 기능입니다!
```

### 왜 이걸 알아야 하나요?

```
"수천 마리 몬스터에 애니메이션을 넣고 싶어요!"

전통적 방식:
├── 몬스터 1000마리 = Actor 1000개
├── SkeletalMeshComponent 1000개
├── AnimBP 1000개 실행
└── 결과: 💀 5fps

Instanced Skeletal Mesh:
├── 몬스터 1000마리 = 컴포넌트 1개
├── 인스턴스 1000개 (경량 데이터)
├── AnimBank 1개 (사전 컴파일)
└── 결과: ✅ 60fps 가능!
```

---

## 1. 아키텍처 개요

### 1.1 시스템 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                 Instanced Skeletal Mesh 아키텍처                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌─────────────────┐          ┌─────────────────────────────┐  │
│   │    AnimBank     │          │  UInstancedSkinnedMeshComp  │  │
│   │  (에셋, 오프라인)│◄────────►│      (런타임 컴포넌트)       │  │
│   │                 │          │                             │  │
│   │  • 시퀀스 목록  │          │  • 인스턴스 배열            │  │
│   │  • 컴파일된 본  │          │  • Transform + AnimIndex    │  │
│   │  • 바운드 정보  │          │  • 커스텀 데이터            │  │
│   └────────┬────────┘          └──────────────┬──────────────┘  │
│            │                                   │                 │
│            ▼                                   ▼                 │
│   ┌─────────────────┐          ┌─────────────────────────────┐  │
│   │ TransformProvider│          │    FInstanceDataManager     │  │
│   │  (UAnimBankData) │          │       (변경 추적)           │  │
│   │                 │          │                             │  │
│   │  • 본 오프셋   │          │  • Add/Remove 추적         │  │
│   │  • 애니 바운드 │          │  • Transform 변경 추적     │  │
│   └────────┬────────┘          │  • ID ↔ Index 매핑         │  │
│            │                   └──────────────┬──────────────┘  │
│            ▼                                   ▼                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                      Scene Proxy                         │   │
│   │  (FInstancedSkinnedMeshSceneProxy / FNaniteISMProxy)    │   │
│   │                                                          │   │
│   │  • GPU 버퍼 관리                                        │   │
│   │  • 인스턴스 컬링                                        │   │
│   │  • 스키닝 실행                                          │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 핵심 클래스

| 클래스 | 역할 | 위치 |
|--------|------|------|
| `UInstancedSkinnedMeshComponent` | 런타임 컴포넌트 | Engine/Components |
| `UAnimBank` | 애니메이션 에셋 | Engine/Animation |
| `UAnimBankData` | TransformProvider 구현 | Engine/Animation |
| `UTransformProviderData` | 추상 인터페이스 | Engine/Animation |
| `FInstanceDataManager` | 인스턴스 변경 추적 | Engine/InstanceData |
| `UHLODInstancedSkinnedMeshComponent` | HLOD용 확장 | Engine/WorldPartition |

---

## 2. AnimBank 시스템 상세

### 2.1 AnimBank란?

**한 줄 요약**: "애니메이션을 미리 구워서 GPU에서 빠르게 재생하는 시스템"

```
일반 AnimBP:                      AnimBank:
┌─────────────────────────┐      ┌─────────────────────────┐
│ 매 프레임 계산:          │      │ 오프라인 컴파일:         │
│                         │      │                         │
│ • 스테이트 머신 평가    │      │ • 모든 프레임의 본       │
│ • 블렌드 계산           │      │   트랜스폼 미리 계산     │
│ • IK 계산               │      │ • 글로벌 공간으로 변환   │
│ • 본 트랜스폼 출력      │      │ • 압축하여 저장          │
│                         │      │                         │
│ CPU 비용: 높음          │      │ CPU 비용: 거의 없음     │
│ 유연성: 최대            │      │ 유연성: 제한적          │
└─────────────────────────┘      └─────────────────────────┘
```

### 2.2 AnimBank 데이터 구조

```cpp
// AnimBank 내 각 시퀀스의 컴파일된 데이터
struct FAnimBankEntry
{
    // 본 트랜스폼 데이터 (글로벌 공간)
    TArray<FVector3f> PositionKeys;   // [FrameCount * BoneCount]
    TArray<FQuat4f> RotationKeys;     // [FrameCount * BoneCount]
    TArray<FVector3f> ScalingKeys;    // [FrameCount * BoneCount] (선택)

    // 바운드 정보 (컬링용)
    FBoxSphereBounds SampledBounds;

    // 재생 설정
    float Position;     // 시작 위치
    float PlayRate;     // 재생 속도
    uint32 FrameCount;  // 총 프레임 수
    uint32 KeyCount;    // FrameCount * BoneCount

    // 플래그
    uint32 Flags;       // ANIM_BANK_FLAG_LOOPING, ANIM_BANK_FLAG_AUTOSTART
};
```

### 2.3 AnimBank 워크플로우

**Step 1: AnimBank 에셋 생성**
```
콘텐츠 브라우저에서:
우클릭 → Animation → AnimBank

스켈레톤 선택 다이얼로그가 나타남
→ 대상 스켈레톤 선택
```

**Step 2: 시퀀스 추가**
```cpp
// AnimBank 에디터 또는 블루프린트에서:
UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Sequences")
TArray<FAnimBankSequence> Sequences;

// 각 시퀀스 설정
struct FAnimBankSequence
{
    UAnimSequence* Sequence;  // 원본 애니메이션
    bool bLooping;            // 루프 여부
    bool bAutoStart;          // 자동 시작
    float Position;           // 시작 위치 (0 ~ PlayLength)
    float PlayRate;           // 재생 속도 (1.0 = 기본)
    float BoundsScale;        // 바운드 스케일 (1.0 ~ 10.0)
};
```

**Step 3: 컴파일**
```
• 에디터에서 자동 컴파일
• Sequences나 Asset 변경 시 자동 트리거
• DDC(Derived Data Cache)에 캐시
• 플랫폼별로 별도 컴파일
```

### 2.4 컴파일 과정 상세

```
AnimBank 컴파일 파이프라인:

1. 의존성 대기
   └─ 참조된 UAnimSequence들이 컴파일 완료될 때까지 대기

2. 스켈레톤 매핑
   └─ UE::AnimBank::BuildSkinnedAssetMapping()
   └─ 메시 스켈레톤 ↔ 애니메이션 스켈레톤 본 인덱스 매핑

3. 애니메이션 압축 해제
   └─ FAnimSequenceDecompressionContext 사용
   └─ 프레임별로 본 트랜스폼 추출

4. 리타게팅 (필요시)
   └─ 메시 스켈레톤 ≠ 애님 스켈레톤인 경우
   └─ 쿼터니언 리타게팅 테이블 적용

5. 공간 변환
   └─ 로컬 본 공간 → 글로벌 메시 공간
   └─ 부모 계층 누적 계산

6. 바운드 계산
   └─ 모든 프레임의 모든 본 위치에서 min/max 계산
   └─ BoundsScale 적용

7. DDC 캐싱
   └─ 플랫폼별 직렬화
   └─ 키 해시: 에셋 해시 + 시퀀스 해시 + 플래그 + 재생 설정
```

### 2.5 메모리 사용량 계산

```cpp
// AnimBank 메모리 사용량 예시
//
// 가정:
// - 60fps 애니메이션
// - 3초 길이
// - 65개 본
// - 스케일 포함

FrameCount = 60 * 3 = 180
BoneCount = 65
KeyCount = 180 * 65 = 11,700

PositionKeys = 11,700 * 12 bytes (FVector3f) = 140.4 KB
RotationKeys = 11,700 * 16 bytes (FQuat4f) = 187.2 KB
ScalingKeys = 11,700 * 12 bytes (FVector3f) = 140.4 KB
                                             ──────────
                                Total per Sequence ≈ 468 KB

// 10개 시퀀스가 있다면:
Total AnimBank ≈ 4.68 MB
```

---

## 3. TransformProvider 시스템

### 3.1 TransformProvider 인터페이스

```cpp
// 추상 베이스 클래스
class UTransformProviderData : public UObject
{
public:
    // 활성화 상태
    virtual bool IsEnabled() const;

    // 고유 ID (GPU/CPU 모드 구분)
    virtual const FGuid& GetTransformProviderID() const;

    // 스켈레톤 배칭 지원 여부
    virtual bool UsesSkeletonBatching() const;

    // 애니메이션 수
    virtual uint32 GetUniqueAnimationCount() const;

    // 바운드 정보
    virtual bool HasAnimationBounds() const;
    virtual bool GetAnimationBounds(uint32 AnimationIndex, FRenderBounds& OutBounds) const;

    // 스키닝 데이터 오프셋 (GPU 버퍼용)
    virtual uint32 GetSkinningDataOffset(
        int32 InstanceIndex,
        const FTransform& ComponentTransform,
        const FSkinnedMeshInstanceData& InstanceData) const;

    // 렌더 스레드 리소스
    virtual FTransformProviderRenderProxy* CreateRenderThreadResources(...);
    virtual void DestroyRenderThreadResources(FTransformProviderRenderProxy* Proxy);

    // 컴파일 상태
    virtual bool IsCompiling() const;
};
```

### 3.2 UAnimBankData 구현

```cpp
// TransformProvider의 주요 구현체
UCLASS(BlueprintType)
class UAnimBankData : public UTransformProviderData
{
public:
    // 블루프린트에서 편집 가능
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Animation")
    TArray<FAnimBankItem> AnimBankItems;

    // FAnimBankItem = AnimBank 에셋 + 시퀀스 인덱스 참조
};

// 사용 예
USTRUCT(BlueprintType)
struct FAnimBankItem
{
    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    TObjectPtr<UAnimBank> BankAsset;

    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    int32 SequenceIndex;
};
```

### 3.3 GPU vs CPU 모드

```cpp
// CVar로 제어
r.AnimBank.GPU = 1  // GPU 모드 (기본, 권장)
r.AnimBank.GPU = 0  // CPU 모드 (폴백)

// 모드에 따른 Provider ID
GPU GUID: {0xA5C0027A, 0x8F884C7C, 0x9312F138, 0x71A9300F}
CPU GUID: {0xE7D6173D, 0x246F431A, 0x912D384E, 0x156C0D2C}
```

**GPU 모드:**
- 본 트랜스폼이 GPU 버퍼에 저장
- 스키닝 계산이 GPU에서 실행
- 대량 인스턴스에 최적

**CPU 모드:**
- 폴백용
- 호환성 문제 시 사용
- 성능 저하 있음

---

## 4. 인스턴스 관리 시스템

### 4.1 인스턴스 데이터 구조

```cpp
// 각 인스턴스가 저장하는 데이터
USTRUCT()
struct FSkinnedMeshInstanceData
{
    // 트랜스폼 (로컬 또는 월드)
    UPROPERTY(EditAnywhere, Category=Instances)
    FTransform3f Transform;

    // AnimBank 내 애니메이션 인덱스
    UPROPERTY(EditAnywhere, Category=Animation)
    uint32 AnimationIndex;
};
```

### 4.2 FInstanceDataManager

```cpp
// 인스턴스 변경 추적 시스템
class FInstanceDataManager
{
public:
    // 추적 상태
    enum class ETrackingState
    {
        Initial,   // 프록시 없음, 추적 안함
        Tracked,   // 활성 추적 중
        Disabled,  // 렌더러 없음
        Optimized  // 델타 추적 없음, 변경 시 전체 리빌드
    };

    // 인스턴스 추가/제거
    FPrimitiveInstanceId Add(int32 InstanceAddAtIndex);
    void RemoveAtSwap(int32 InstanceIndex);
    void RemoveAt(int32 InstanceIndex);

    // 변경 알림
    void TransformChanged(int32 InstanceIndex);
    void TransformsChangedAll();
    void CustomDataChanged(int32 InstanceIndex);

    // ID ↔ Index 변환
    int32 IdToIndex(FPrimitiveInstanceId Id) const;
    FPrimitiveInstanceId IndexToId(int32 Index) const;

    // 변경사항 플러시 (렌더 스레드로)
    void FlushChanges(FInstanceDataManagerSourceDataDesc&& Desc);
};
```

### 4.3 ID 시스템의 중요성

```cpp
// 왜 ID가 필요한가?

// 문제 상황: Swap 기반 제거
Instances = [A, B, C, D, E]
           Index: 0  1  2  3  4

// B 제거 (RemoveAtSwap)
Instances = [A, E, C, D]
           Index: 0  1  2  3

// 인덱스가 바뀜! E가 1로 이동
// 외부에서 "인덱스 1의 인스턴스"를 참조하면 틀림!

// 해결책: FPrimitiveInstanceId
ID_A = Add(0) → 항상 A를 가리킴
ID_B = Add(1) → 제거됨
ID_E = Add(4) → 항상 E를 가리킴 (인덱스가 바뀌어도!)

// ID로 접근
GetInstanceTransform(ID_E, ...) // 항상 E의 트랜스폼 반환
```

### 4.4 인스턴스 API

```cpp
// 인스턴스 추가
UFUNCTION(BlueprintCallable, Category="Components|InstancedSkinnedMesh")
FPrimitiveInstanceId AddInstance(
    const FTransform& InstanceTransform,
    int32 AnimationIndex,
    bool bWorldSpace = false
);

// 배치 추가
TArray<FPrimitiveInstanceId> AddInstances(
    const TArray<FTransform>& Transforms,
    const TArray<int32>& AnimationIndices,
    bool bShouldReturnIds,
    bool bWorldSpace = false
);

// 인스턴스 제거
UFUNCTION(BlueprintCallable, Category="Components|InstancedSkinnedMesh")
bool RemoveInstance(FPrimitiveInstanceId InstanceId);

void RemoveInstances(const TArray<FPrimitiveInstanceId>& InstancesToRemove);

UFUNCTION(BlueprintCallable, Category="Components|InstancedSkinnedMesh")
void ClearInstances();

// 트랜스폼 조회/수정
UFUNCTION(BlueprintCallable, Category="Components|InstancedSkinnedMesh")
bool GetInstanceTransform(
    FPrimitiveInstanceId InstanceId,
    FTransform& OutInstanceTransform,
    bool bWorldSpace = false
) const;

// 애니메이션 인덱스 조회
bool GetInstanceAnimationIndex(
    FPrimitiveInstanceId InstanceId,
    int32& OutAnimationIndex
) const;
```

---

## 5. 커스텀 데이터 시스템

### 5.1 개념

```
커스텀 데이터 = 인스턴스별 float 배열
           = 머티리얼에서 읽을 수 있는 파라미터

사용 예:
├── 색상 변화 (R, G, B)
├── 마모/손상 정도
├── 팀 컬러 인덱스
├── 특수 효과 강도
└── 무엇이든 float로 표현 가능!
```

### 5.2 메모리 레이아웃

```cpp
// NumCustomDataFloats = 3인 경우

InstanceCustomData 배열:
┌─────────────────────────────────────────────────┐
│ Inst0_Data0 │ Inst0_Data1 │ Inst0_Data2 │       │
│ Inst1_Data0 │ Inst1_Data1 │ Inst1_Data2 │       │
│ Inst2_Data0 │ Inst2_Data1 │ Inst2_Data2 │       │
│ ...         │ ...         │ ...         │       │
└─────────────────────────────────────────────────┘

// 인스턴스 N의 데이터 M 접근:
Index = N * NumCustomDataFloats + M
```

### 5.3 API

```cpp
// 커스텀 데이터 개수 설정
UFUNCTION(BlueprintCallable, Category="Components|InstancedSkinnedMesh")
void SetNumCustomDataFloats(int32 InNumCustomDataFloats);

// 단일 값 설정
UFUNCTION(BlueprintCallable, Category="Components|InstancedSkinnedMesh")
bool SetCustomDataValue(
    FPrimitiveInstanceId InstanceId,
    int32 CustomDataIndex,
    float CustomDataValue
);

// 배열로 설정/조회
bool SetCustomData(
    FPrimitiveInstanceId InstanceId,
    TArrayView<const float> CustomDataFloats
);

bool GetCustomData(
    FPrimitiveInstanceId InstanceId,
    TArrayView<float> CustomDataFloats
) const;
```

### 5.4 머티리얼에서 사용

```
머티리얼 에디터:

1. PerInstanceCustomData 노드 추가
2. Data Index 설정 (0, 1, 2...)
3. 출력을 원하는 파라미터에 연결

예: 팀 컬러 시스템
┌─────────────────────────────────────┐
│ PerInstanceCustomData [Index: 0] ──►│ Lerp Alpha
│                                     │
│ TeamColor_A (파랑) ───────────────►│ Lerp A
│ TeamColor_B (빨강) ───────────────►│ Lerp B
│                                     │
│ Lerp Output ─────────────────────►│ Base Color
└─────────────────────────────────────┘
```

---

## 6. GPU-Only 인스턴스

### 6.1 개념

```
일반 인스턴스:
├── CPU 측에 데이터 존재
├── GPU 측에도 복사본 존재
├── CPU → GPU 동기화 필요
└── 개별 인스턴스 제어 가능

GPU-Only 인스턴스:
├── CPU 측에 데이터 없음!
├── GPU 측에만 존재
├── 동기화 오버헤드 없음
├── 개별 제어 불가
└── Compute Shader에서 생성/관리
```

### 6.2 API

```cpp
// GPU-Only 모드 설정
void SetInstanceDataGPUOnly(bool bInInstancesGPUOnly);

// GPU 인스턴스 개수 설정
void SetNumGPUInstances(int32 InCount);

// 상태 확인
bool UsesGPUOnlyInstances() const { return bIsInstanceDataGPUOnly; }
int32 GetInstanceCountGPUOnly() const { return NumInstancesGPUOnly; }
```

### 6.3 사용 시나리오

```
GPU-Only가 적합한 경우:
├── 수만 개 이상의 인스턴스
├── Compute Shader로 위치 계산 (파티클, 시뮬레이션)
├── 개별 인스턴스 제어가 필요 없음
└── 극한의 성능 필요

GPU-Only가 부적합한 경우:
├── 에디터에서 선택/편집 필요
├── 게임플레이에서 개별 접근 필요
├── 히트 테스트/충돌 감지 필요
└── 디버깅 중
```

---

## 7. 컬링 및 LOD 시스템

### 7.1 애니메이션 스크린 사이즈 컷오프

```cpp
float AnimationMinScreenSize = 0.0f;

// 값의 의미:
// 0.0f  → 글로벌 임계값 사용 (기본)
// < 0   → 컷오프 비활성화 (항상 애니메이션)
// > 0   → 스크린 스페이스 풋프린트 임계값
```

**동작 원리:**
```
화면에서 인스턴스 크기 < AnimationMinScreenSize
        ↓
애니메이션 재생 중지 (T-Pose 또는 첫 프레임 고정)
        ↓
GPU 스키닝 비용 절약!
```

### 7.2 거리 기반 컬링

```cpp
int32 InstanceMinDrawDistance;    // 이 거리 이상에서만 렌더링
int32 InstanceStartCullDistance;  // 페이드 아웃 시작
int32 InstanceEndCullDistance;    // 완전히 사라짐

// API
void SetCullDistances(int32 StartCullDistance, int32 EndCullDistance);
void GetCullDistances(int32& OutStart, int32& OutEnd) const;
```

**컬링 다이어그램:**
```
거리 →  0          Min       Start        End         ∞
        │          │         │            │           │
        │ 보이지   │         │   페이드   │ 보이지    │
        │ 않음     │  정상   │   아웃     │ 않음      │
        │          │  렌더링 │            │           │
        ▼──────────▼─────────▼────────────▼───────────▼
```

### 7.3 바운드 시스템

```cpp
// 애니메이션 바운드 (TransformProvider에서)
bool GetAnimationBounds(uint32 AnimationIndex, FRenderBounds& OutBounds);

// 수동 바운드 오버라이드
FBox PrimitiveBoundsOverride;
void SetPrimitiveBoundsOverride(const FBox& InBounds);
FBox GetPrimitiveBoundsOverride() const;
```

**바운드 스케일링:**
```cpp
// AnimBank 시퀀스에서 설정
FAnimBankSequence {
    float BoundsScale = 1.0f;  // UI 범위: 1.0 ~ 10.0
};

// 바운드가 너무 작으면?
// → 애니메이션이 바운드 밖으로 나가면 갑자기 사라짐!
// → BoundsScale을 키워서 보수적으로 설정
```

---

## 8. Nanite 통합

### 8.1 Nanite 스키닝

```cpp
// Nanite 지원 Scene Proxy
class FNaniteInstancedSkinnedMeshSceneProxy : public Nanite::FSkinnedSceneProxy
{
    // Nanite의 고급 지오메트리 LOD + 인스턴싱
};
```

### 8.2 Nanite 활성화 조건

```cpp
// 활성화 조건 체크
if (bShouldNaniteSkin)
{
    // 머티리얼 감사
    Nanite::FMaterialAudit NaniteMaterials{};
    Nanite::FNaniteResourcesHelper::AuditMaterials(&Desc, NaniteMaterials, true);

    // 마스킹 허용 여부
    bool bIsMaskingAllowed = Nanite::IsMaskingAllowed(World, false);

    // 유효성 검사 통과 시 Nanite 프록시 생성
    if (NaniteMaterials.IsValid(bIsMaskingAllowed))
    {
        return new FNaniteInstancedSkinnedMeshSceneProxy(...);
    }
}
// 폴백: 일반 GPU 스킨 프록시
return new FInstancedSkinnedMeshSceneProxy(...);
```

### 8.3 Nanite의 장점

```
Nanite + Instanced Skeletal Mesh:

├── 계층적 Z 컬링
│   └─ 보이지 않는 지오메트리 조기 제거
│
├── 버텍스 셰이딩 감소
│   └─ 필요한 삼각형만 처리
│
├── 메시 LOD 자동 관리
│   └─ Nanite가 알아서 세부도 조절
│
├── 대규모 클러스터링
│   └─ 인스턴스 공간 그룹화
│
└── 단점: 일부 머티리얼 제한
    └─ Translucent, World Position Offset 등 제한
```

---

## 9. HLOD 통합

### 9.1 UHLODInstancedSkinnedMeshComponent

```cpp
// HLOD 전용 확장 컴포넌트
UCLASS()
class UHLODInstancedSkinnedMeshComponent : public UInstancedSkinnedMeshComponent
{
    // HLOD 빌드 시 배치된 여러 소스 컴포넌트를 하나로 병합
};
```

### 9.2 HLOD 빌드 과정

```
HLOD 빌드 (HLODBuilder.cpp):

1. 소스 컴포넌트 수집
   └─ 레벨 내 모든 InstancedSkinnedMeshComponent 찾기

2. 디스크립터별 그룹화
   └─ 같은 스켈레탈 에셋 + 머티리얼 + 설정

3. 배치 생성
   for (같은 디스크립터를 가진 컴포넌트들):
       FInstancedSkinnedMeshBatch batch
       batch.Add(sourceComponent, filterFunction)

4. HLOD 컴포넌트 생성
   UHLODInstancedSkinnedMeshComponent* hlodComp =
       batch.ISMComponentDescriptor->CreateComponent()
   batch.ISMComponentBatcher.InitComponent(hlodComp)
```

### 9.3 HLOD 제한사항

```
HLOD에서 지원되지 않는 것:

❌ Movable 모빌리티 (Static/Stationary만)
❌ 런타임 물리/충돌
❌ 런타임 히트 테스트
❌ 게임플레이 인터랙션
❌ 인스턴스 개별 제어

HLOD의 목적:
✅ 원거리 LOD 최적화
✅ 드로우 콜 감소
✅ 메모리 효율화
✅ 정적 군중 표현
```

---

## 10. 실전 활용 시나리오

### 10.1 군중 렌더링

```cpp
// 시나리오: 스타디움에 10,000명 관중

// 1. AnimBank 준비
UAnimBank* CrowdAnimBank;
// - Idle_Sitting (앉아서 대기)
// - Cheer_A, Cheer_B, Cheer_C (환호)
// - Wave_Left, Wave_Right (파도타기)

// 2. 컴포넌트 설정
UInstancedSkinnedMeshComponent* CrowdComp;
CrowdComp->SetSkinnedAsset(CrowdSkeletalMesh);
CrowdComp->SetTransformProvider(CrowdAnimBankData);
CrowdComp->SetNumCustomDataFloats(2); // 팀컬러, 변형

// 3. 인스턴스 생성
for (const FSeatData& Seat : StadiumSeats)
{
    int32 AnimIndex = FMath::RandRange(0, 5); // 랜덤 애니메이션
    FPrimitiveInstanceId Id = CrowdComp->AddInstance(
        Seat.Transform,
        AnimIndex,
        true // WorldSpace
    );

    // 커스텀 데이터: 팀 컬러
    CrowdComp->SetCustomDataValue(Id, 0, Seat.bHomeTeam ? 0.0f : 1.0f);
    // 커스텀 데이터: 외형 변형
    CrowdComp->SetCustomDataValue(Id, 1, FMath::FRand());
}

// 4. 컬링 설정
CrowdComp->AnimationMinScreenSize = 0.01f; // 아주 작을 때 애니 정지
CrowdComp->SetCullDistances(0, 50000); // 500m에서 페이드 아웃
```

### 10.2 원거리 몬스터 (Mass AI 보조)

```cpp
// 시나리오: Mass AI와 함께 사용
// - 가까운 몬스터: Mass AI Actor (풀 애니메이션)
// - 먼 몬스터: Instanced Skeletal Mesh (간단 애니)

// 1. AnimBank 준비 (단순 애니만)
UAnimBank* MonsterDistantAnimBank;
// - Idle_Loop
// - Walk_Loop
// - Run_Loop (3개면 충분)

// 2. 컴포넌트 설정
UInstancedSkinnedMeshComponent* DistantMonsters;

// 3. Mass AI LOD 전환 시 처리
void OnMassLODChanged(FMassEntityHandle Entity, EMassLOD::Type NewLOD)
{
    if (NewLOD == EMassLOD::Low)
    {
        // Mass의 Static ISM → Skeletal ISM으로 전환
        FTransform EntityTransform = GetEntityTransform(Entity);
        int32 AnimIndex = IsMoving(Entity) ? 1 : 0; // Walk or Idle

        FPrimitiveInstanceId Id = DistantMonsters->AddInstance(
            EntityTransform, AnimIndex, true);

        // 엔티티-인스턴스 매핑 저장
        EntityToInstanceMap.Add(Entity, Id);
    }
    else if (PrevLOD == EMassLOD::Low)
    {
        // 다시 가까워짐 → 인스턴스 제거
        if (FPrimitiveInstanceId* Id = EntityToInstanceMap.Find(Entity))
        {
            DistantMonsters->RemoveInstance(*Id);
            EntityToInstanceMap.Remove(Entity);
        }
    }
}
```

### 10.3 캐릭터 커스터마이징 미리보기

```cpp
// 시나리오: 캐릭터 선택 화면에서 100개 커스텀 캐릭터 표시

// 1. 각 커스터마이징 옵션별 AnimBank
UAnimBank* PreviewAnimBank;
// - Idle_Preview (한 개면 충분)

// 2. 인스턴스별 커스텀 데이터로 외형 제어
SetNumCustomDataFloats(8);
// [0-2]: 피부색 RGB
// [3-5]: 헤어색 RGB
// [6]: 헬멧 타입
// [7]: 갑옷 타입

// 3. 머티리얼에서 PerInstanceCustomData 사용
// → 각 인스턴스가 다른 외형으로 표시됨!
```

---

## 11. 제한사항 및 주의점

### 11.1 핵심 제한사항

```
┌─────────────────────────────────────────────────────────────┐
│                    핵심 제한사항 요약                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. 실험적 기능                                             │
│     └─ API 변경 가능성                                      │
│     └─ 프로덕션 사용 위험                                   │
│                                                              │
│  2. AnimBank 사전 컴파일                                    │
│     └─ 런타임 새 애니메이션 추가 불가                       │
│     └─ 동적 블렌딩 제한                                     │
│                                                              │
│  3. 인스턴스별 본 제어 불가                                 │
│     └─ IK 없음                                              │
│     └─ 래그돌 없음                                          │
│     └─ 물리 시뮬레이션 없음                                 │
│                                                              │
│  4. 게임플레이 기능 부재                                    │
│     └─ 충돌 감지 없음                                       │
│     └─ 히트 테스트 (에디터만)                               │
│     └─ AI 통합 없음                                         │
│                                                              │
│  5. GPU-Only 제한                                           │
│     └─ 에디터 선택 불가                                     │
│     └─ CPU에서 접근 불가                                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 11.2 AnimBank 제한 상세

```
AnimBank가 할 수 없는 것:

❌ 실시간 블렌딩
   └─ A → B 애니메이션 전환 시 즉시 전환
   └─ AnimBP처럼 부드러운 크로스페이드 불가

❌ 런타임 애니메이션 추가
   └─ 에디터에서 컴파일해야 함
   └─ DLC로 새 애니 추가? 재빌드 필요

❌ 프로시저럴 애니메이션
   └─ Look At, Aim Offset 등 불가
   └─ 본을 코드로 직접 제어 불가

❌ 모프 타겟
   └─ 현재 지원 안함

❌ 클로스/피직스
   └─ 시뮬레이션 없음
```

### 11.3 성능 vs 유연성 트레이드오프

```
                성능                      유연성
                 ▲                          ▲
                 │                          │
Instanced       │████████████              │██
Skeletal        │                          │
                │                          │
                │                          │
Static          │██████████████████        │
ISM             │                          │
                │                          │
                │                          │
Traditional     │██                        │████████████████████
Skeletal        │                          │
                └──────────────────────────┴──────────────────────►
                                       선택
```

---

## 12. 디버깅 및 CVar

### 12.1 주요 CVar

```cpp
// 레퍼런스 포즈 강제 (애니메이션 무시)
r.InstancedSkinnedMeshes.ForceRefPose = 0
// 1로 설정 시 모든 인스턴스가 T-Pose

// 애니메이션 바운드 사용
r.InstancedSkinnedMeshes.AnimationBounds = 1
// 0이면 레퍼런스 포즈 바운드 사용

// AnimBank GPU 모드
r.AnimBank.GPU = 1
// 0이면 CPU 폴백

// 비동기 컴파일 동시성
a.AnimBank.AsyncCompilation.MaxConcurrency = 4
// AnimBank 병렬 컴파일 개수

// 메모리 제한
Memory.MemoryForAnimBankAssetCompile = 512
// AnimBank 컴파일용 메모리 (MiB)

// 레이 트레이싱
r.RayTracing.Geometry.InstancedSkeletalMeshes = 1
// 0이면 레이 트레이싱에서 제외
```

### 12.2 디버깅 팁

```
문제: 인스턴스가 안 보여요

체크리스트:
□ TransformProvider가 설정되어 있나?
□ AnimBank가 컴파일 완료되었나? (IsCompiling() == false)
□ 인스턴스 개수가 0이 아닌가?
□ 컬링 거리 내에 있나?
□ AnimationIndex가 유효한 범위인가?

---

문제: 애니메이션이 안 재생돼요

체크리스트:
□ r.InstancedSkinnedMeshes.ForceRefPose = 0 인가?
□ AnimationMinScreenSize 보다 화면 크기가 큰가?
□ AnimBank 시퀀스가 올바르게 설정되었나?
□ bLooping/bAutoStart 플래그 확인

---

문제: 성능이 예상보다 안 좋아요

체크리스트:
□ GPU 모드 사용 중인가? (r.AnimBank.GPU = 1)
□ Nanite 활성화 가능한가?
□ 컬링 거리 적절한가?
□ AnimationMinScreenSize 설정했나?
□ 인스턴스 수 확인 (1만 개 초과?)
```

---

## 13. 결론 및 체크리스트

### 13.1 Instanced Skeletal Mesh 사용 결정 가이드

```
질문 1: 수백~수천 개의 동일 스켈레탈 메시가 필요한가요?
├─ YES → 질문 2로
└─ NO → 일반 SkeletalMeshComponent 사용

질문 2: 게임플레이 인터랙션 (충돌, 히트, AI)이 필요한가요?
├─ YES → ⚠️ Instanced Skeletal Mesh는 부적합
│        → 전통적 Actor 기반 또는 Mass AI + Actor 하이브리드
└─ NO → 질문 3으로

질문 3: 복잡한 애니메이션 (블렌딩, IK, 물리)이 필요한가요?
├─ YES → ⚠️ Instanced Skeletal Mesh는 부적합
│        → AnimBP가 필요하면 Actor 사용
└─ NO → 질문 4로

질문 4: 실험적 기능 사용 리스크를 감수할 수 있나요?
├─ YES → ✅ Instanced Skeletal Mesh 적합!
└─ NO → Static ISM + 가까운 곳만 Actor 하이브리드
```

### 13.2 최종 체크리스트

```
Instanced Skeletal Mesh 구현 체크리스트:

□ 스켈레톤 호환 확인
□ AnimBank 에셋 생성
□ 필요한 애니메이션 시퀀스 추가
□ 바운드 스케일 적절히 설정
□ UInstancedSkinnedMeshComponent 생성
□ TransformProvider (UAnimBankData) 설정
□ 인스턴스 추가 로직 구현
□ 커스텀 데이터 개수 설정 (필요시)
□ 머티리얼에서 PerInstanceCustomData 사용 (필요시)
□ 컬링 거리 설정
□ AnimationMinScreenSize 설정
□ 테스트 및 프로파일링
```

---

## 참고 문서

- [10_InstancedSkeletalMeshAnalysis.md](10_InstancedSkeletalMeshAnalysis.md) - Mass AI 통합 분석
- [03_RenderingAndLOD.md](03_RenderingAndLOD.md) - LOD 시스템 일반
- [04_AnimationIntegration.md](04_AnimationIntegration.md) - 애니메이션 통합

---

## 참조 소스 경로

```
핵심 파일:
├── Classes/Components/InstancedSkinnedMeshComponent.h
├── Private/Components/InstancedSkinnedMeshComponent.cpp
├── Classes/Animation/AnimBank.h
├── Private/Animation/AnimBank.cpp
├── Private/Animation/AnimBankCompiler.h
├── Private/Animation/AnimBankCompiler.cpp
├── Public/Animation/TransformProviderData.h
├── Public/InstanceData/InstanceDataManager.h
├── Public/WorldPartition/HLOD/HLODInstancedSkinnedMeshComponent.h
└── Shaders/Shared/SkinningDefinitions.h
```

---

## 버전 히스토리

| 버전 | 날짜 | 변경 내용 |
|------|------|----------|
| v1.0 | 2025-12-30 | 초기 문서 작성 |

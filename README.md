# app-traffic-analytics

> 글로벌 커머스 Mobile App Traffic 데이터마트 쿼리  
> *Data mart query for global e-commerce mobile app traffic analytics*

[![SQL](https://img.shields.io/badge/SQL-DuckDB-yellow?style=flat-square)](https://duckdb.org)
[![Version](https://img.shields.io/badge/version-1.6.4-blue?style=flat-square)]()

---

## 배경 / Background

글로벌 커머스 서비스의 Mobile App 데이터가 웹 BI 대시보드와 기준이 달라  
**Single Source of Truth** 구축이 필요한 상황에서 설계한 데이터마트 쿼리입니다.

- 기존 문제: App 데이터 태깅 미완성 기간 동안 GA 데이터와 BI 대시보드(visit 기준) 간 수치 불일치
- 해결 방향: GA Raw 데이터를 BI 기준으로 재설계, Division·마케팅 채널 Breakdown까지 확장

---

## 데이터 파이프라인 구조 / Pipeline Structure

```
app_traffic_raw (Raw Event Log)
    │
    ├── params              ← 날짜 범위 파라미터
    ├── in_view_cart        ← 이벤트별 item 정보 정규화
    ├── cids                ← 마케팅 채널 분류 (20개+ CID 패턴)
    ├── total_for_daily_    ← 로그인 상태 / 사업 유형 분류
    ├── total_for_daily     ← 세션 단위 통합
    ├── atc                 ← Add-to-Cart 타임스탬프
    ├── purchase_event      ← 구매 이력 (신규/재구매 판별)
    ├── final_daily_mart_   ← 사용자·세션·제품·채널 결합
    └── final_daily_mart    ← MAU/WAU 날짜 파생 + 최종 마트
            │
            └── OUTPUT: DAU / MAU / WAU 통합 집계
```

---

## 주요 기능 / Key Features

### 1. 마케팅 채널 자동 분류 (20개+ CID 패턴)
CID 값을 정규식으로 파싱하여 채널을 자동 분류합니다.

| 채널 | 분류 기준 |
|---|---|
| PLA | `pla-ecomm`, `pla-`, `pla_` 패턴 |
| Paid Search | `sem`, `ppc`, `pcc` 패턴 |
| Display Retargeting | `dis-cnvr`, `disrtg-ecomm` 패턴 |
| Email | `eml-ecom`, `emlcom-`, `emlcrm-` 등 세분화 |
| Social (Paid) | `smc`, `smp`, `ecomfb` 패턴 |
| Push Notifications | `pnf`, `psh` 패턴 |
| Affiliate | `afl` 패턴 |
| Natural Search / Direct | UTM 기반 분류 |

### 2. 제품 Division 분류
SKU 패턴 기반으로 3개 사업부 자동 분류:
- **IM** (Mobile/IT): 스마트폰, 태블릿, 웨어러블
- **VD** (영상/디스플레이): TV, 모니터, 프로젝터
- **HA** (생활가전): 냉장고, 세탁기, 에어컨

### 3. 사업 유형 분류
- **B2C** / **SMB** (B2B) / **EPP** (임직원 구매) 자동 판별

### 4. DAU / MAU / WAU 통합 산출
`GROUPING SETS`를 활용하여 단일 쿼리로 일/월/주 지표를 동시 산출합니다.

```sql
GROUP BY GROUPING SETS (
    (event_date, event_date_mau, event_date_wau, country_cd, platform, biz_type, product_division),
    (event_date, event_date_mau, event_date_wau, country_cd, platform, biz_type)
)
```

### 5. Funnel 단계별 지표
```
shopper_visit → pdp_visit → add_to_cart_visit → 
cart_page_visit → checkout_page_visit → order_visit → orders → revenue
```

### 6. 신규/재구매 고객 판별
2년치 구매 이력을 기반으로 신규(`new_ordered_visitor`) / 재구매(`exist_ordered_visitor`) 자동 분류

---

## 출력 스키마 / Output Schema

| 컬럼 | 설명 |
|---|---|
| `event_date_local` | 이벤트 날짜 |
| `country_cd` | 국가 코드 |
| `biz_type` | 사업 유형 (B2C / SMB / EPP) |
| `platform` | 플랫폼 (iOS / Android) |
| `product_division` | 제품 사업부 (IM / VD / HA / ALL) |
| `channel_group3` | 마케팅 채널 |
| `shopper_visit` | 방문자 수 (DAU) |
| `pdp_visit` | 상품 상세 페이지 방문 |
| `add_to_cart_visit` | 장바구니 담기 |
| `cart_page_visit` | 장바구니 페이지 방문 |
| `checkout_page_visit` | 결제 페이지 방문 |
| `order_visit` | 주문 완료 방문 |
| `orders` | 주문 건수 |
| `revenue` | 매출 |
| `adobe_app_*` | Adobe Analytics 기반 앱 사용자 지표 |
| `time_spent` | 평균 체류 시간 (초) |

---

## 사용 방법 / Usage

```sql
-- 1. params 테이블에서 날짜 범위 설정
CREATE TEMP TABLE params AS
SELECT '2024-10-01'::DATE AS extract_startdate, 
       '2024-10-31'::DATE AS extract_enddate;

-- 2. app_traffic_raw 테이블을 실제 데이터 소스로 교체
-- 3. 쿼리 실행 후 BI 대시보드에 연결
```

**샘플 데이터로 테스트:**
```bash
# DuckDB CLI 설치 후
duckdb < app_traffic_datamart.sql
```

---

## 기술 스택 / Tech Stack

`DuckDB` `SQL` `GROUPING SETS` `Window Functions` `REGEXP_MATCHES` `Google Analytics`

---

## 설계 의도 / Design Notes

- **모듈형 TEMP TABLE 구조**: 각 단계를 독립적으로 디버깅 가능
- **GROUPING SETS 활용**: Division별 / 전체 집계를 단일 쿼리로 처리
- **채널 분류 우선순위**: CASE WHEN 순서로 채널 간 중복 방지
- **사업 유형 우선순위**: SMB → EPP → B2C 순서로 세션 기반 재분류

---

## 작성자 / Author

**조영광 (YoungGwang Cho)**  
Analytics Engineer  
[LinkedIn](https://linkedin.com/in/young-kwang-cho-0838382a4) · [GitHub](https://github.com/YK124)

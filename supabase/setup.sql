-- 이벤트 연장/종료 확인 — Supabase 초기 설정 스크립트
-- Supabase 대시보드 > SQL Editor 에서 이 스크립트 전체를 한 번 실행하면 됩니다.
-- 여러 번 실행해도 안전합니다 (이미 있는 테이블·정책·데이터는 건드리지 않습니다).
--
-- 저장 구조: 배너 및 단말 관리(app_state 한 행에 전체 JSON)와 달리, 구분과 항목을 각각 한 행씩
-- 저장한다. 화면에서 칸 하나를 고치면 그 행의 그 칸만 UPDATE 하므로, 여러 사람이 동시에
-- 다른 행이나 다른 칸을 고쳐도 서로의 입력을 덮어쓰지 않는다.

-- 1. 테이블 ---------------------------------------------------------------
create table if not exists eec_sections (
  id          text primary key,
  sort_order  double precision not null default 0,
  name        text not null default '',
  note        text not null default '',
  updated_at  timestamptz not null default now()
);

create table if not exists eec_rows (
  id          text primary key,
  section_id  text not null references eec_sections(id) on delete cascade,
  sort_order  double precision not null default 0,
  urgent      boolean not null default false,          -- 마감 임박 (행 노란색)
  cat         text not null default '',                -- 이벤트 및 단말 · 대분류
  sub         text not null default '',                -- 이벤트 및 단말 · 소분류
  checks      jsonb not null default '[]'::jsonb,      -- 확인 사항: [{ "label": 구분("운영 기간" 또는 직접 입력), "at": "YYYY-MM-DDTHH:MM"(24시) }]
  area        text not null default '',                -- 적용 영역
  extend      text not null default '' check (extend in ('', 'Y', 'N')),  -- 기간 연장
  reply       text not null default '',                -- 추가 내용 기재
  team        text not null default '',                -- 요청자 · 팀
  owner       text not null default '',                -- 요청자 · 담당자
  memo        text not null default '',                -- 비고
  updated_at  timestamptz not null default now()
);
create index if not exists eec_rows_section_idx on eec_rows(section_id);

-- updated_at 자동 갱신
create or replace function eec_touch() returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists eec_sections_touch on eec_sections;
create trigger eec_sections_touch before update on eec_sections for each row execute function eec_touch();
drop trigger if exists eec_rows_touch on eec_rows;
create trigger eec_rows_touch before update on eec_rows for each row execute function eec_touch();

-- 2. 접근 권한 --------------------------------------------------------------
--    로그인 기능이 없으므로 링크와 anon key를 아는 사람은 누구나 읽고 쓸 수 있다
--    (배너 및 단말 관리와 같은 수준). 더 좁히려면 Supabase Auth + 사용자별 정책으로 확장.
alter table eec_sections enable row level security;
alter table eec_rows enable row level security;

drop policy if exists "anon all eec_sections" on eec_sections;
create policy "anon all eec_sections" on eec_sections for all to anon using (true) with check (true);
drop policy if exists "anon all eec_rows" on eec_rows;
create policy "anon all eec_rows" on eec_rows for all to anon using (true) with check (true);

grant usage on schema public to anon;
grant select, insert, update, delete on eec_sections, eec_rows to anon;

-- 3. 실시간 동기화 ----------------------------------------------------------
--    한 사람이 고친 내용이 다른 사람 화면에 바로 반영되도록 변경 이벤트를 브로드캐스트한다.
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'eec_sections') then
    alter publication supabase_realtime add table eec_sections;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'eec_rows') then
    alter publication supabase_realtime add table eec_rows;
  end if;
end $$;

-- 4. 초기 데이터 (공식온라인스토어 26년 10월 진행중인 이벤트 연장 건_v0.1 '확인 부탁 드립니다!' 탭) ----
--    이미 같은 id가 있으면 건너뛰므로, 다시 실행해도 팀이 고친 내용을 되돌리지 않는다.

insert into eec_sections (id, sort_order, name, note) values
  ('s1', 0, '진행중인 이벤트 (모바일 온라인 가입혜택)', '* 변경 내용 및 연장 여부 확인 필요. 별도 수정 사항 없으시면 Y 처리만 부탁드립니다.'),
  ('s2', 1, '진행중인 이벤트 (너겟)', '* 변경 내용 및 연장 여부 확인 필요. 별도 수정 사항 없으시면 Y 처리만 부탁드립니다.'),
  ('s3', 2, '빌보드 배너', '* 변경 내용 및 연장 여부 확인 필요. 별도 수정 사항 없으시면 Y 처리만 부탁드립니다.'),
  ('s4', 3, '이벤트 배너', '* 변경 내용 및 연장 여부 확인 필요. 별도 수정 사항 없으시면 Y 처리만 부탁드립니다.'),
  ('s5', 4, '단말목록 상단 배너', '* 변경 내용 및 연장 여부 확인 필요. 별도 수정 사항 없으시면 Y 처리만 부탁드립니다.'),
  ('s6', 5, '팝업', '* 변경 내용 및 연장 여부 확인 필요. 별도 수정 사항 없으시면 Y 처리만 부탁드립니다.'),
  ('s7', 6, 'USP 상단 제조사 프로모션', '* 변경 내용 및 연장 여부 확인 필요. 별도 수정 사항 없으시면 Y 처리만 부탁드립니다.
* 연장/종료 티켓에서는 전시 세팅만 관리하며 프로모션 수정 건은 각각의 티켓으로 생성 부탁 드립니다.')
on conflict (id) do nothing;

insert into eec_rows (id, section_id, sort_order, cat, sub, checks, area, team, owner) values
  ('r1', 's1', 0, '모듈 이벤트', 'iPhone 최대 지원금 혜택', '[{"label": "운영 기간", "at": "2026-11-30T23:59"}]'::jsonb, '✦STG: 진행 제외
✦운영: 82221', '디지털커머스팀', '복다솜'),
  ('r2', 's1', 1, '', 'iPhone Duo 출시 기념 이벤트', '[{"label": "운영 기간", "at": "2026-10-26T23:59"}]'::jsonb, '✦STG: 2921
✦운영: 82570', '디지털채널혁신팀', '서효정'),
  ('r3', 's1', 2, '모듈 이벤트', '갤럭시 브랜드관', '[{"label": "운영 기간", "at": "2026-10-31T23:59"}]'::jsonb, '✦STG: 진행 제외
✦운영: 82534', '디지털커머스팀', '문가을'),
  ('r4', 's1', 3, '외부 이벤트', '10월 Npay 3,000P 적립!', '[{"label": "운영 기간", "at": "2026-10-31T23:59"}]'::jsonb, '✦STG: 2525
✦운영: 82203', '디지털그로스마케팅팀', '김정연'),
  ('r5', 's1', 4, '(히든) MO·App 전용/ 모듈 이벤트', '갤럭시·iPhone17 시리즈 시크릿 단말 할인 혜택', '[{"label": "운영 기간", "at": "2026-11-30T23:59"}]'::jsonb, '✦STG: 진행 제외
✦운영: 82571', '디지털커머스팀', '박상인'),
  ('r6', 's1', 5, '(히든) MO·App 전용 이벤트', 'U+one앱 간편 이용안내', '[{"label": "운영 기간", "at": "2026-12-31T23:59"}]'::jsonb, '✦STG: 2632
✦운영: 82296', '디지털채널혁신팀', '이민애'),
  ('r7', 's1', 6, '', '신분증 인증/안면 인증 추가 안내', '[{"label": "운영 기간", "at": "2026-12-31T23:59"}]'::jsonb, '✦STG: 2593
✦운영: 82258', '디지털채널혁신팀', '손범열'),
  ('r8', 's1', 7, '', '친구 추천 이벤트', '[{"label": "운영 기간", "at": "2026-12-31T16:59"}]'::jsonb, '✦STG: 1307
✦운영: 81244', '디지털커머스팀', '문가을,복다솜,박상인'),
  ('r9', 's1', 8, '', '중고폰 갤럭시 시리즈의 특별혜택', '[{"label": "운영 기간", "at": "2026-12-31T16:59"}]'::jsonb, '✦STG: 239
✦운영: 239', '디지털커머스팀', '이승민'),
  ('r10', 's2', 0, '', '10월 너겟 친구 추천 이벤트', '[{"label": "운영 기간", "at": "2026-10-31T23:59"}]'::jsonb, '✦STG: 2597
✦운영: 82262', '디지털커머스팀', '문지원'),
  ('r11', 's2', 1, '', '가입하고 너겟 혜택 받자', '[{"label": "운영 기간", "at": "2026-12-31T23:59"}]'::jsonb, '✦STG: 2026
✦운영: 81875', '', ''),
  ('r12', 's2', 2, '', '온라인 전용 요금제, 너겟', '[{"label": "운영 기간", "at": "2026-12-31T23:59"}]'::jsonb, '✦STG: 2492
✦운영: 82173', '', ''),
  ('r13', 's3', 0, '', 'iPhone Duo 애플브랜드관', '[{"label": "운영 기간", "at": "2026-11-30T23:59"}]'::jsonb, '', '디지털커머스팀', '문가을'),
  ('r14', 's3', 1, '', 'Galaxy Z Foldable 8 최대 혜택', '[{"label": "운영 기간", "at": "2026-10-31T23:59"}]'::jsonb, '', '디지털커머스팀', '문가을'),
  ('r15', 's3', 2, '', '(S26기획전)갤럭시 심플하게 더 잘사는 방법!', '[{"label": "운영 기간", "at": "2026-10-31T23:59"}]'::jsonb, '', '디지털커머스팀', '박상인'),
  ('r16', 's3', 3, '', 'iPhone 18 프로 최대 혜택 앞으로', '[{"label": "운영 기간", "at": "2026-12-31T16:59"}]'::jsonb, '', '디지털커머스팀', '문가을'),
  ('r17', 's3', 4, '', '10월 너겟 친구 추천', '[{"label": "운영 기간", "at": "2026-12-31T16:59"}]'::jsonb, '', '디지털커머스팀', '문가을'),
  ('r18', 's4', 0, '', '프리미엄 중고폰', '[{"label": "운영 기간", "at": "2026-12-31T23:59"}]'::jsonb, '', '디지털커머스팀', '유영헌'),
  ('r19', 's5', 0, '', 'iPhone Duo 애플브랜드관', '[{"label": "운영 기간", "at": "2026-11-30T23:59"}]'::jsonb, '- 노출 영역: 휴대폰/ 태블릿/ 워치', '디지털커머스팀', '문가을'),
  ('r20', 's5', 1, '', 'Galaxy Z Foldable 8 최대 혜택', '[{"label": "운영 기간", "at": "2026-10-31T23:59"}]'::jsonb, '- 노출 영역: 휴대폰/ 태블릿/ 워치', '디지털커머스팀', '문가을'),
  ('r21', 's5', 2, '', 'S26 프로모션_갤럭시 심플하게 더 잘사는 방법!', '[{"label": "운영 기간", "at": "2026-10-31T23:59"}]'::jsonb, '- 노출 영역: 휴대폰/ 태블릿/ 워치', '디지털커머스팀', '문가을'),
  ('r22', 's5', 3, '', 'iPhone 18 프로 최대 혜택 앞으로', '[{"label": "운영 기간", "at": "2026-12-31T16:59"}]'::jsonb, '- 노출 영역: 휴대폰/ 태블릿/ 워치', '디지털커머스팀', '문가을'),
  ('r23', 's5', 4, '', '10월 너겟 친구 추천', '[{"label": "운영 기간", "at": "2026-12-31T23:59"}]'::jsonb, '- 노출 영역: 휴대폰/ 태블릿/ 워치', '디지털커머스팀', '문가을'),
  ('r24', 's5', 5, '', '휴대폰 지원금 안내', '[{"label": "운영 기간", "at": "2026-12-31T16:59"}]'::jsonb, '- 노출 영역: 태블릿/ 워치', '디지털커머스팀', '문가을,복다솜,박상인'),
  ('r25', 's5', 6, '', '신분증 인증/안면 인증 추가 안내', '[{"label": "운영 기간", "at": "2026-12-31T23:59"}]'::jsonb, '- 노출 영역: 휴대폰', '디지털채널혁신팀', '손범열'),
  ('r26', 's5', 7, '', 'iPad Pro M5 시리즈', '[{"label": "운영 기간", "at": "2026-12-31T16:59"}]'::jsonb, '- 노출 영역: 태블릿', '디지털커머스팀', '최종원'),
  ('r27', 's6', 0, '', 'iPhone Duo 512GB 소진 안내', '[{"label": "운영 기간", "at": "2026-12-31T23:59"}]'::jsonb, '- iPhone Duo 512GB', '', ''),
  ('r28', 's6', 1, '', '배송 일주일 이상 지연 안내', '[{"label": "운영 기간", "at": "2026-12-31T23:59"}]'::jsonb, '- iPhone Duo 256GB
-  iPhone Duo 1TB
-  iPhone Duo 2TB', '', ''),
  ('r29', 's7', 0, '', '갤럭시 Z 폴더블8', '[{"label": "[갤럭시 어텀 페스타] · 스마트태그3 & 케이스 30% 할인 쿠폰  증정 · 구매·개통", "at": "2026-10-31T23:59"}, {"label": "[갤럭시 어텀 페스타] · 스마트태그3 & 케이스 30% 할인 쿠폰  증정 · 신청", "at": "2026-11-30T23:59"}, {"label": "[갤럭시 리뷰 챌린지] · 단말구매·개통", "at": "2026-10-31T23:59"}, {"label": "[갤럭시 리뷰 챌린지] · 리뷰 작성 및 응모", "at": "2026-11-08T23:59"}, {"label": "[갤럭시 리뷰 챌린지] · 당첨자 발표", "at": "2026-11-18T23:59"}, {"label": "[중고폰 최대 10만원 추가보상 혜택] · 단말구매·개통", "at": "2026-10-31T23:59"}, {"label": "[중고폰 최대 10만원 추가보상 혜택] · 추가보상 신청 및 중고기기 반납", "at": "2026-10-31T23:59"}, {"label": "[초기 구매 혜택] · 단말구매·개통", "at": "2026-09-30T23:59"}, {"label": "[초기 구매 혜택] · 쿠폰사용", "at": "2028-10-31T23:59"}, {"label": "[콘텐츠 구독 혜택] · 혜택1) 구글 AI 프로 6개월 구독권 · 단말 구매·개통 및 사용 등록", "at": "2027-08-01T23:59"}, {"label": "[콘텐츠 구독 혜택] · 혜택2) 윌라 3개월 구독권 · 단말구매·개통", "at": "2026-10-31T23:59"}, {"label": "[콘텐츠 구독 혜택] · 혜택2) 윌라 3개월 구독권 · 쿠폰사용", "at": "2026-11-30T23:59"}, {"label": "[보호필름 무료 부착 서비스] · 단말구매·개통", "at": "2027-07-31T23:59"}, {"label": "[보호필름 무료 부착 서비스] · 쿠폰사용", "at": "2028-07-31T23:59"}, {"label": "[갤럭시 스토어 특별 혜택] · 테마 다운로드", "at": "2026-10-31T23:59"}]'::jsonb, '- Z Fold8 256GB
- Z Fold8 512GB
- Z Fold8 1TB
- Z Fold8 Ultra 256GB
- Z Fold8 Ultra 512GB
- Z Fold8 Ultra 1TB
- 갤럭시 Z Flip8 256GB
- 갤럭시 Z Flip8 512GB', '디지털커머스팀', '최종원'),
  ('r30', 's7', 1, '', '갤럭시 S26 FE', '[{"label": "[갤럭시 어텀 페스타] · 스마트태그3 & 케이스 30% 할인 쿠폰  증정 · 구매·개통", "at": "2026-10-31T23:59"}, {"label": "[갤럭시 어텀 페스타] · 스마트태그3 & 케이스 30% 할인 쿠폰  증정 · 신청", "at": "2026-11-30T23:59"}, {"label": "[갤럭시 리뷰 챌린지] · 단말구매·개통", "at": "2026-10-31T23:59"}, {"label": "[갤럭시 리뷰 챌린지] · 리뷰 작성 및 응모", "at": "2026-11-08T23:59"}, {"label": "[갤럭시 리뷰 챌린지] · 당첨자 발표", "at": "2026-11-18T23:59"}, {"label": "[중고폰 최대 10만원 추가보상 혜택] · 단말구매·개통", "at": "2026-10-31T23:59"}, {"label": "[중고폰 최대 10만원 추가보상 혜택] · 추가보상 신청 및 중고기기 반납", "at": "2026-10-31T23:59"}, {"label": "[케이스&액세서리 혜택] · 단말구매·개통", "at": "2026-10-31T23:59"}, {"label": "[케이스&액세서리 혜택] · 쿠폰사용", "at": "2026-11-30T23:59"}, {"label": "[콘텐츠 구독 혜택] · 혜택1) 구글 AI 프로 6개월 구독권 · 단말 구매·개통 및 사용 등록", "at": "2027-08-01T23:59"}, {"label": "[콘텐츠 구독 혜택] · 혜택2) 윌라 2개월 구독권 · 단말구매·개통", "at": "2026-10-31T23:59"}, {"label": "[콘텐츠 구독 혜택] · 혜택2) 윌라 2개월 구독권 · 사용등록", "at": "2026-12-31T23:59"}]'::jsonb, '- 갤럭시 S26 FE', '디지털커머스팀', '최종원'),
  ('r31', 's7', 2, '', 'S26 시리즈', '[{"label": "[갤럭시 어텀 페스타] · 스마트태그3 & 케이스 30% 할인 쿠폰  증정 · 구매·개통", "at": "2026-10-31T23:59"}, {"label": "[갤럭시 어텀 페스타] · 스마트태그3 & 케이스 30% 할인 쿠폰  증정 · 신청", "at": "2026-11-30T23:59"}, {"label": "[갤럭시 리뷰 챌린지] · 단말구매·개통", "at": "2026-10-31T23:59"}, {"label": "[갤럭시 리뷰 챌린지] · 리뷰 작성 및 응모", "at": "2026-11-08T23:59"}, {"label": "[갤럭시 리뷰 챌린지] · 당첨자 발표", "at": "2026-11-18T23:59"}, {"label": "[중고폰 최대 10만원 추가보상 혜택] · 단말구매·개통", "at": "2026-10-31T23:59"}, {"label": "[중고폰 최대 10만원 추가보상 혜택] · 추가보상 신청 및 중고기기 반납", "at": "2026-10-31T23:59"}]'::jsonb, '-S26+ 256GB
- S26+ 512GB
- S26 256GB
- S26 512GB
- S26 U 256GB
- S26 U 512GB
- S26 U 1TB', '디지털커머스팀', '최종원'),
  ('r32', 's7', 3, '', '갤럭시 A37 5G', '[{"label": "[구매 혜택] · 윌라 2개월 구독권 · 단말구매", "at": "2026-09-30T23:59"}, {"label": "[구매 혜택] · 윌라 2개월 구독권 · 사용등록", "at": "2026-10-31T23:59"}]'::jsonb, 'https://www.lguplus.com/mobile/device/samsung/galaxy-a37/SM-A376N', '디지털커머스팀', '최종원'),
  ('r33', 's7', 4, '', '키즈폰 무너에디션2', '[{"label": "[무너폰2의 스페셜 혜택] · 이벤트1) 교보라플 키즈 케어보험 1년 무료 보장 · 기간", "at": "2026-12-31T23:59"}, {"label": "[무너폰2의 스페셜 혜택] · 이벤트2) 하나은행 아이부자 7천원 용돈 · 기간", "at": "2026-12-31T23:59"}]'::jsonb, 'https://www.lguplus.com/mobile/device/samsung/uplus-kidsphone-mooner-2/SM-A175N-M2', '디지털커머스팀', '최종원'),
  ('r34', 's7', 5, '', '갤럭시 워치 Ultra2', '[{"label": "[갤럭시 워치 울트라2 ｜워치9 구매혜택] · 론칭 구매 혜택1) 워치 밴드 할인 쿠폰 증정 · 구매 기간", "at": "2026-08-31T23:59"}, {"label": "[갤럭시 워치 울트라2 ｜워치9 구매혜택] · 론칭 구매 혜택1) 워치 밴드 할인 쿠폰 증정 · 쿠폰 신청 및 사용 기간", "at": "2026-09-30T23:59"}, {"label": "[갤럭시 워치 울트라2 ｜워치9 구매혜택] · 론칭 구매 혜택2) 타임플릭 워치페이스 6개월 이용권 증정 · 쿠폰 다운로드 기간", "at": "2026-09-30T23:59"}, {"label": "[갤럭시 워치 울트라2 ｜워치9 구매혜택] · 론칭 구매 혜택2) 타임플릭 워치페이스 6개월 이용권 증정 · 쿠폰 등록 기간", "at": "2026-12-31T23:59"}, {"label": "[갤럭시 워치 울트라2 ｜워치9 구매혜택] · 구매자 혜택 리뷰) 워꾸 챌린지 · 챌린지 인증 기간", "at": "2026-09-14T23:59"}, {"label": "[갤럭시 워치 울트라2 ｜워치9 구매혜택] · 구매자 혜택 리뷰) 워꾸 챌린지 · 혜택 당첨 발표일", "at": "2026-09-21T23:59"}]'::jsonb, '- 갤럭시 워치 Ultra2
- 갤럭시 워치9 44mm
- 갤럭시 워치9 40mm', '디지털커머스팀', '최종원'),
  ('r35', 's7', 6, '', '갤럭시 탭 S12 Ultra', '[{"label": "[런칭 스페셜 혜택] · 혜택2) · 기간", "at": "2026-08-01T23:59"}, {"label": "[런칭 스페셜 혜택] · 혜택3) · 기간", "at": "2026-10-31T23:59"}, {"label": "[런칭 스페셜 혜택] · 혜택3) · 등록", "at": "2026-11-08T23:59"}, {"label": "[정품 액세서리 할인 혜택] · 구매", "at": "2026-10-31T23:59"}, {"label": "[정품 액세서리 할인 혜택] · 신청", "at": "2026-11-08T23:59"}]'::jsonb, '- 갤럭시 탭 S12 Ultra
- 갤럭시 탭 S12+', '디지털커머스팀', '최종원')
on conflict (id) do nothing;

-- 5. API(PostgREST)가 새 테이블을 바로 인식하도록 스키마 캐시를 갱신한다.
notify pgrst, 'reload schema';

-- 확인용: 아래 결과가 sections 7 / rows 35 이면 설정 완료.
select (select count(*) from eec_sections) as sections, (select count(*) from eec_rows) as rows;

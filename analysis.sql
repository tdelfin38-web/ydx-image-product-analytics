
-- 1. Диапазон и объём выборки.
SELECT
    MIN(event_at) AS first_event_at,
    MAX(event_at) AS last_event_at,
    COUNT(*) AS events_count
FROM search_events;

-- 2. Объём событий по платформам.
SELECT
    pl.platform_name,
    COUNT(*) AS events_count
FROM search_events AS ev
JOIN platforms AS pl ON pl.platform_id = ev.platform_id
GROUP BY pl.platform_name
ORDER BY events_count DESC;

-- 3. Запросы с текстом «ютуб» по платформам.
SELECT
    pl.platform_name,
    COUNT(*) AS youtube_queries
FROM search_events AS ev
JOIN search_queries AS qu ON qu.query_id = ev.query_id
JOIN platforms AS pl ON pl.platform_id = ev.platform_id
WHERE LOWER(qu.query_text) LIKE '%ютуб%'
GROUP BY pl.platform_name
ORDER BY youtube_queries DESC;

-- 4. Топ-10 запросов на каждой платформе.
WITH ranked AS (
    SELECT
        pl.platform_name,
        qu.query_text,
        COUNT(*) AS queries_count,
        ROW_NUMBER() OVER (
            PARTITION BY pl.platform_name
            ORDER BY COUNT(*) DESC, qu.query_text
        ) AS rank_in_platform
    FROM search_events AS ev
    JOIN search_queries AS qu ON qu.query_id = ev.query_id
    JOIN platforms AS pl ON pl.platform_id = ev.platform_id
    GROUP BY pl.platform_name, qu.query_text
), ranked_top AS (
    SELECT
        platform_name,
        rank_in_platform,
        query_text,
        queries_count,
        ROW_NUMBER() OVER (
            ORDER BY queries_count ASC, platform_name, query_text
        ) AS sort_order_asc
    FROM ranked
    WHERE rank_in_platform <= 10
)
SELECT
    platform_name,
    rank_in_platform,
    query_text,
    queries_count,
    sort_order_asc
FROM ranked_top
ORDER BY sort_order_asc;

-- 5. Суточный профиль: количество и доля внутри платформы.
WITH hourly AS (
    SELECT
        pl.platform_name,
        EXTRACT(HOUR FROM ev.event_at AT TIME ZONE 'Europe/Moscow')::int AS hour_of_day,
        COUNT(*) AS queries_count
    FROM search_events AS ev
    JOIN platforms AS pl ON pl.platform_id = ev.platform_id
    GROUP BY pl.platform_name, hour_of_day
)
SELECT
    platform_name,
    hour_of_day,
    queries_count,
    ROUND(
        100.0 * queries_count / SUM(queries_count) OVER (PARTITION BY platform_name),
        2
    ) AS queries_share_pct
FROM hourly
ORDER BY platform_name, hour_of_day;

-- 6. Контрастные тематики.
WITH themed_events AS (
    SELECT
        pl.platform_name,
        CASE
            WHEN LOWER(qu.query_text) ~ '(фильм|сериал|кино)' THEN 'кино и сериалы'
            WHEN LOWER(qu.query_text) ~ '(собака|кот|кошка|животн)' THEN 'животные'
            WHEN LOWER(qu.query_text) ~ '(диван|кухн|интерьер|дизайн)' THEN 'дом и интерьер'
            WHEN LOWER(qu.query_text) ~ '(школ|урок|учеб)' THEN 'учёба'
            ELSE 'прочее'
        END AS topic
    FROM search_events AS ev
    JOIN search_queries AS qu ON qu.query_id = ev.query_id
    JOIN platforms AS pl ON pl.platform_id = ev.platform_id
), topic_shares AS (
    SELECT
        platform_name,
        topic,
        COUNT(*) AS queries_count,
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY platform_name) AS share_pct
    FROM themed_events
    GROUP BY platform_name, topic
)
SELECT
    topic,
    MAX(queries_count) FILTER (WHERE platform_name = 'desktop') AS desktop_queries,
    MAX(queries_count) FILTER (WHERE platform_name = 'touch') AS touch_queries,
    ROUND(MAX(share_pct) FILTER (WHERE platform_name = 'desktop'), 2) AS desktop_share_pct,
    ROUND(MAX(share_pct) FILTER (WHERE platform_name = 'touch'), 2) AS touch_share_pct,
    ROUND(
        MAX(share_pct) FILTER (WHERE platform_name = 'touch')
        - MAX(share_pct) FILTER (WHERE platform_name = 'desktop'),
        2
    ) AS touch_minus_desktop_pp
FROM topic_shares
GROUP BY topic
ORDER BY ABS(
    MAX(share_pct) FILTER (WHERE platform_name = 'touch')
    - MAX(share_pct) FILTER (WHERE platform_name = 'desktop')
) DESC;

-- 7. Доля контрастных тематик и прочего от всех событий выборки.
WITH themed_events AS (
    SELECT
        pl.platform_name,
        CASE
            WHEN LOWER(qu.query_text) ~ '(фильм|сериал|кино|собака|кот|кошка|животн|диван|кухн|интерьер|дизайн|школ|урок|учеб)'
                THEN 'Контрастные тематики'
            ELSE 'Прочее'
        END AS query_group
    FROM search_events AS ev
    JOIN search_queries AS qu ON qu.query_id = ev.query_id
    JOIN platforms AS pl ON pl.platform_id = ev.platform_id
)
SELECT
    query_group,
    platform_name,
    COUNT(*) AS queries_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS all_queries_share_pct
FROM themed_events
GROUP BY query_group, platform_name
ORDER BY query_group, platform_name;

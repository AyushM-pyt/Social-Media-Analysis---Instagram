use ig_clone ;
-- ====================================================================================================================

-- DATA QUALITY CHECK: NULL AND DUPLICATE RECORDS

-- ---------- USERS ----------
-- Null check
select *
from ig_clone.users
where username is NULL
   or created_at is NULL;

-- Duplicate check (excluding id)
select username, COUNT(*) as occurrences
from ig_clone.users
group by username
having COUNT(*) > 1;

-- ---------- COMMENTS ----------
-- Null check
select *
from ig_clone.comments
where comment_text is NULL
   or user_id is NULL
   or photo_id is NULL
   or created_at is NULL;

-- Duplicate check (excluding id)
select comment_text, user_id, photo_id, created_at, COUNT(*) as occurrences
from ig_clone.comments
group by comment_text, user_id, photo_id, created_at
having COUNT(*) > 1;

-- ---------- FOLLOWS ----------
-- Null check
select *
from ig_clone.follows
where follower_id is NULL
   or followee_id is NULL
   or created_at is NULL;

-- Duplicate check
select follower_id, followee_id, COUNT(*) as occurrences
from ig_clone.follows
group by follower_id, followee_id
having COUNT(*) > 1;


-- ---------- LIKES ----------
-- Note: likes has a composite key (user_id + photo_id), same reasoning as follows.

-- Null check
select *
from ig_clone.likes
where user_id is NULL
   or photo_id is NULL
   or created_at is NULL;

-- Duplicate check
select user_id, photo_id, COUNT(*) as occurrences
from ig_clone.likes
group by user_id, photo_id
having COUNT(*) > 1;

-- ---------- PHOTO_TAGS ----------
-- Note: composite key (photo_id + tag_id)

-- Null check
select *
from ig_clone.photo_tags
where photo_id is NULL
   or tag_id is NULL;

-- Duplicate check
select photo_id, tag_id, COUNT(*) as occurrences
from ig_clone.photo_tags
group by photo_id, tag_id
having COUNT(*) > 1;

-- ---------- PHOTOS ----------
-- Null check
select *
from ig_clone.photos
where image_url is NULL
   or user_id is NULL
   or created_at is NULL;

-- Duplicate check (excluding id)
select image_url, user_id, created_at, COUNT(*) as occurrences
from ig_clone.photos
group by image_url, user_id, created_at
having COUNT(*) > 1;

-- ---------- TAGS ----------
-- Null check
select *
from ig_clone.tags
where tag_name is NULL
   or created_at is NULL;

-- Duplicate check (excluding id)
select tag_name, COUNT(*) as occurrences
from ig_clone.tags
group by tag_name
having COUNT(*) > 1;



-- =======================================================================================================

-- USER ACTIVITY DISTRIBUTION

with post_count as (
	select user_id, COUNT(*) as no_of_posts_byuser
	from photos 
	group by user_id
),
likes_count as (
	select user_id, COUNT(*) as no_of_likes_byuser
	from likes 
	group by user_id
),
comment_count as (
	select user_id, COUNT(*) as no_of_comments_byuser
	from comments
	group by user_id 
),
user_activity as (
	select u.id as user_id, 
		coalesce(p.no_of_posts_byuser,0)  + coalesce(l.no_of_likes_byuser,0) + coalesce(c.no_of_comments_byuser,0) as total_activity
	from users u
	left join post_count p on u.id = p.user_id
	left join comment_count c on u.id = c.user_id 
	left join likes_count l on u.id = l.user_id 
)
select 
	case when total_activity >= 0 and total_activity <= 20 then 'inactive'
		 when total_activity >= 21 and total_activity <= 200 then 'moderately active'
         when total_activity > 200 then 'highly active'
         end as activity_category,
         COUNT(*) as user_count
from user_activity
group by  activity_category ;
-- ============================================================================================================

-- AVERAGE TAGS PER POST

select ROUND(AVG(tag_count), 2) as avg_tags_per_post
from (
    select p.id,
        COUNT(pt.tag_id) as tag_count
    from photos p
    left join photo_tags pt
        on p.id = pt.photo_id
    group by p.id
) as photo_tag_counts;

-- =============================================================================================================

-- TOP USERS BY ENGAGEMENT

with like_counts as (
    select p.user_id, count(l.user_id) as total_likes
    from photos p
    join likes l on p.id = l.photo_id
    group by p.user_id
),
comment_counts as (
    select p.user_id, count(c.id) as total_comments
    from photos p
    join comments c on p.id = c.photo_id
    group by p.user_id
),
user_engagement as (
    select u.id as user_id, u.username,
        (coalesce(l.total_likes, 0) + coalesce(c.total_comments, 0)) as total_engagement_received,
        dense_rank() over(order by (coalesce(l.total_likes, 0) + coalesce(c.total_comments, 0)) desc) as user_rank
    from users u
    join photos p on u.id = p.user_id
    left join like_counts l on u.id = l.user_id
    left join comment_counts c on u.id = c.user_id
    group by u.id, u.username, l.total_likes, c.total_comments
)
select *
from user_engagement
where user_rank <= 5;


-- =============================================================================================================

-- USERS WITH HIGHEST FOLLOWERS AND FOLLOWINGS

with followers as (
	select followee_id,
		COUNT(*) as follower_cnt
	from follows
	group by followee_id
),
followings as (
	select follower_id,
		COUNT(*) as followings_cnt
	from follows
	group by follower_id
)
select u.id, u.username,
	coalesce(f.follower_cnt,0) as follower_cnt,
	coalesce(f1.followings_cnt,0) as followings_cnt,
	DENSE_RANK() over(order by coalesce(f.follower_cnt,0) desc, coalesce(f1.followings_cnt,0) desc) as rnk
from users u
left join followers f
	on u.id = f.followee_id
left join followings f1
	on u.id = f1.follower_id
order by follower_cnt desc, followings_cnt desc;

-- =============================================================================================================

-- AVERAGE ENGAGEMENT PER POST BY USER

with posts_engagement as (
	select p.user_id, p.id,
		COUNT(distinct l.user_id) + COUNT(distinct c.id) as post_engagement
	from photos p
	left join likes l
		on p.id = l.photo_id
	left join comments c
		on p.id = c.photo_id
	group by p.user_id, p.id
)
select u.id, username,
	ROUND(coalesce(AVG(post_engagement),0),2) as average_engagement_rate
from users u
left join posts_engagement pe
	on u.id = pe.user_id
group by u.id, username;

-- =============================================================================================================

-- USERS WHO HAVE NEVER LIKED A POST

select *
from users
where not exists ( select 1 from likes where likes.user_id = users.id ) ;

select u.id, username, photo_id as liked_photo
from users u
left join likes l on u.id = l.user_id
where photo_id is NULL ;

-- =============================================================================================================

-- HASHTAG USAGE AND ENGAGEMENT ANALYSIS

-- identify most used tags
-- Identifying Tags with highest engagements recieved on it..!
with post_engagement as (					-- Calculating users engagement on their post.
	select p.id as photo_id, COUNT(distinct l.user_id) + COUNT(distinct c.id) as total_engagement
	from users u 
	join photos p on u.id = p.user_id 
	left join likes l on p.id = l.photo_id
	left join comments c on p.id = c.photo_id
	group by p.id
)
select tag_id, tag_name, COUNT(pt.photo_id) as no_of_timesused, SUM(total_engagement) as total_engagement_recieved
from post_engagement pe
join photo_tags pt on pe.photo_id = pt.photo_id
join tags t on pt.tag_id = t.id
group by tag_id, tag_name
order by total_engagement_recieved desc ;

-- =============================================================================================================

-- TOTAL LIKES, COMMENTS, AND PHOTO TAGS BY USER

with likes_count as (
    select
        p.user_id,
        COUNT(*) as total_likes
    from photos p
    join likes l
        on p.id = l.photo_id
    group by p.user_id
),
comments_count as (
    select
        p.user_id,
        COUNT(*) as total_comments
    from photos p
    join comments c
        on p.id = c.photo_id
    group by p.user_id
),
tags_count as (
    select
        p.user_id,
        COUNT(*) as total_tags
    from photos p
    join photo_tags pt
        on p.id = pt.photo_id
    group by p.user_id
)
select
    u.id,
    u.username,
    coalesce(l.total_likes, 0) as total_likes,
    coalesce(c.total_comments, 0) as total_comments,
    coalesce(t.total_tags, 0) as total_photo_tags
from users u
left join likes_count l
    on u.id = l.user_id
left join comments_count c
    on u.id = c.user_id
left join tags_count t
    on u.id = t.user_id
order by total_likes desc,
         total_comments desc,
         total_photo_tags desc;
         
-- ===========================================================================================================

-- MONTHLY USER ENGAGEMENT RANKING

with monthly_engagement as (
	select u.id as user_id, u.username,
		DATE_FORMAT(p.created_at,'%y-%m') as activity_month,
		COUNT(distinct l.user_id) as total_likes,
		COUNT(distinct c.id) as total_comments,
		COUNT(distinct l.user_id)+COUNT(distinct c.id) as total_engagement
	from users u
	join photos p
		on u.id=p.user_id
	left join likes l
		on p.id=l.photo_id
	left join comments c
		on p.id=c.photo_id
	group by u.id, u.username, activity_month
)
select *,
	DENSE_RANK() over(
		partition by activity_month
		order by total_engagement desc
	) as engagement_rank
from monthly_engagement
order by activity_month, engagement_rank;
    
-- ===========================================================================================================

-- HASHTAGS BY AVERAGE POST LIKES

with photo_likes as (
    select
        p.id as photo_id,
        COUNT(l.user_id) as total_likes
    from photos p
    left join likes l
        on p.id = l.photo_id
    group by p.id
),
hashtag_avg_likes as (
    select
        t.id as tag_id,
        t.tag_name,
        ROUND(AVG(pl.total_likes), 2) as avg_likes
    from tags t
    join photo_tags pt
        on t.id = pt.tag_id
    join photo_likes pl
        on pt.photo_id = pl.photo_id
    group by
        t.id,
        t.tag_name
)
select *
from hashtag_avg_likes
order by avg_likes desc;

-- ===========================================================================================================


-- USERS WHO FOLLOWED BACK

select
    u.id,
    u.username,
    f1.followee_id as followed_user,
    f1.created_at as followed_back_on
from follows f1
join follows f2
    on f1.follower_id = f2.followee_id
   and f1.followee_id = f2.follower_id
join users u
    on u.id = f1.follower_id
-- WHERE f1.created_at > f2.created_at 			-- commented out this because in dataset every users have the same timestamp.
;


-- ====================================================================================================================

-- MOST LOYAL OR VALUABLE USERS

with post_counts as (
    select user_id, COUNT(id) as total_posts
    from photos
    group by user_id
),
like_counts as (
    select p.user_id, COUNT(l.user_id) as total_likes
    from photos p
    join likes l on p.id = l.photo_id
    group by p.user_id
),
comment_counts as (
    select p.user_id, COUNT(c.id) as total_comments
    from photos p
    join comments c on p.id = c.photo_id
    group by p.user_id
),
user_metrics as (
    select u.id, u.username,
        COALESCE(p.total_posts, 0) as total_posts,
        COALESCE(l.total_likes, 0) as total_likes,
        COALESCE(c.total_comments, 0) as total_comments,
        (COALESCE(l.total_likes, 0) + COALESCE(c.total_comments, 0)) as total_engagement
    from users u
    left join post_counts p ON u.id = p.user_id
    left join like_counts l ON u.id = l.user_id
    left join comment_counts c ON u.id = c.user_id
)
select *,
    ROUND(total_engagement / NULLIF(total_posts, 0), 2) as avg_engagement_per_post,
    DENSE_RANK() OVER(
        order by total_engagement desc,
                 total_engagement / NULLIF(total_posts, 0) desc
    ) as user_rank
from user_metrics;


-- =================================================================================================================

-- HASHTAGS WITH HIGHEST ENGAGEMENT

with photo_engagement as (
	select p.id as photo_id, COUNT(distinct l.user_id) +
		COUNT(distinct c.id) as total_engagement
	from photos p
	left join likes l on p.id = l.photo_id
	left join comments c on p.id = c.photo_id
	group by p.id
)
select t.id, t.tag_name, COUNT(pe.photo_id) as no_of_timesused,
	ROUND(AVG(total_engagement),2) as avg_engagement,
    SUM(pe.total_engagement) as total_engagement
from tags t 
join photo_tags pt on t.id = pt.tag_id
join photo_engagement pe on pt.photo_id = pe.photo_id
group by t.id , t.tag_name
order by avg_engagement desc, total_engagement desc
; 

-- =================================================================================================================

-- USER ENGAGEMENT BY POSTING TIME

-- Posting Hourly analysis.
with photo_engagement as (
    select
        p.id as photo_id,
        hour(p.created_at) as posting_hour,
        COUNT(distinct l.user_id) +
        COUNT(distinct c.id) as total_engagement
    from photos p
    left join likes l
        on p.id = l.photo_id
    left join comments c
        on p.id = c.photo_id
    group by
        p.id,
        hour(p.created_at)
)

select
    posting_hour,
    COUNT(*) as total_posts,
    ROUND(AVG(total_engagement),2) as avg_engagement
from photo_engagement
group by posting_hour
order by avg_engagement desc;

-- =================================================================================================================

-- INFLUENCER CANDIDATES BY FOLLOWERS AND ENGAGEMENT

with followers as (
    select followee_id,
        count(*) as follower_count
    from follows
    group by followee_id
),
post_counts as (
    select user_id, count(id) as total_posts
    from photos
    group by user_id
),
like_counts as (
    select p.user_id, count(l.user_id) as total_likes
    from photos p
    join likes l on p.id = l.photo_id
    group by p.user_id
),
comment_counts as (
    select p.user_id, count(c.id) as total_comments
    from photos p
    join comments c on p.id = c.photo_id
    group by p.user_id
),
user_engagement as (
    select u.id as user_id, u.username,
        (coalesce(l.total_likes, 0) + coalesce(c.total_comments, 0)) as total_engagement,
        round((coalesce(l.total_likes, 0) + coalesce(c.total_comments, 0)) / nullif(p.total_posts, 0),2) as avg_engagement_per_post
    FROM users u
    join post_counts p on u.id = p.user_id
    left join like_counts l on u.id = l.user_id
    left join comment_counts c on u.id = c.user_id
)
select ue.user_id, ue.username,
    coalesce(f.follower_count, 0) as follower_count,
    ue.total_engagement,
    ue.avg_engagement_per_post,
    dense_rank() over (
        order by
            coalesce(f.follower_count, 0) desc,
            ue.total_engagement desc
    ) as engagement_rank
from user_engagement ue
left join followers f on ue.user_id = f.followee_id
order by engagement_rank;


-- =================================================================================================================

-- UPDATE ENGAGEMENT TYPE FROM LIKE TO HEART

update user_interactions
set engagement_type = 'heart'
where engagement_type = 'like';

-- ============================================== xxxxxxxxxxxxxxxxxxxxxxxx ==============================================================
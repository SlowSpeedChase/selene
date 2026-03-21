#!/usr/bin/env python3
"""
Generate ~500 fictional notes for the Selene dev environment.

Persona: Alex, 31, software engineer with ADHD in Los Angeles.
Domains: work (Mise recipe app), learning (ceramics), health (ADHD), personal, random.
Span: Nov 15 2025 - Feb 15 2026, Pacific Time.

Usage: python3 scripts/generate-dev-fixture.py
Output: fixtures/dev-seed-notes.json
"""

import json
import random
import os
from datetime import datetime, timedelta

random.seed(42)  # Reproducible

# --- Content pools organized by domain and thread ---

WORK_MISE = [
    {"title": "Mise API architecture decision", "content": "Been going back and forth on REST vs GraphQL for Mise. REST is simpler and I know it well, but GraphQL would let the mobile app fetch exactly what it needs. For a recipe app, the nested data (recipe -> ingredients -> steps) maps really well to GraphQL. But then I need to learn Apollo Server properly and that's another thing on the pile. Going with REST for v1. Ship it.", "tags": ["#mise", "#api"]},
    {"title": "Mise ingredient parser progress", "content": "Got the ingredient parser working! It can now handle '2 cups flour', 'a pinch of salt', and even '1 1/2 tbsp olive oil'. The fraction handling was tricky - had to normalize unicode fractions first. Edge cases with ranges still need work ('2-3 cloves garlic'). But this is the core of the whole app so it needs to be solid.", "tags": ["#mise", "#work"]},
    {"title": "Mise search ranking", "content": "Finally cracked the recipe search ranking algorithm. Combining text relevance (BM25) with a popularity score and freshness boost. The results feel way more natural now. Before, searching 'quick pasta' would return a 4-hour bolognese recipe first because it mentioned 'quick prep'. Now the 15-minute aglio e olio comes up top.", "tags": ["#mise", "#api"]},
    {"title": "Mise auth strategy", "content": "Going with JWT for Mise authentication. Considered session-based but JWT is better for the mobile app since it's stateless. Will store refresh tokens in httpOnly cookies for the web client. Need to figure out token rotation strategy - don't want users getting logged out randomly.", "tags": ["#mise", "#api"]},
    {"title": "Mise image upload bug", "content": "Spent all morning debugging the recipe image upload. The compression was too aggressive - everything looked like a watercolor painting. Fixed by bumping quality to 85 and using sharp instead of jimp. Also added WebP conversion with JPEG fallback. File sizes dropped 60% with barely visible quality loss.", "tags": ["#mise", "#work"]},
    {"title": "Mise database decision", "content": "Architecture decision: going with PostgreSQL for Mise instead of SQLite. The ingredient matching queries are deeply relational - 'find recipes using any 3 of these 5 ingredients' is way more natural in SQL with proper joins. Plus I'll want full-text search eventually and pg_trgm is amazing.", "tags": ["#mise", "#api"]},
    {"title": "Mise meal planning feature", "content": "Product idea for Mise: meal planning. Users pick recipes for the week, app generates a consolidated grocery list grouped by store aisle. The grocery list part is the killer feature - deduplicating ingredients across recipes ('2 cups flour from recipe A + 1 cup from recipe B = 3 cups total'). This is v2 though. Don't scope creep.", "tags": ["#mise", "#idea"]},
    {"title": "Mise onboarding flow", "content": "Thinking about Mise onboarding. Users should be able to import recipes from URLs on the first screen - that gives immediate value. Scrape the recipe with a structured data parser (most food blogs use schema.org Recipe markup). Then they have a populated app from minute one instead of staring at an empty library.", "tags": ["#mise", "#work"]},
    {"title": "Mise social features brainstorm", "content": "What if Mise had social features? Follow friends, see what they're cooking this week. Like Strava but for cooking. 'Alex made Pad Thai 3 times this month' kind of activity feed. Could be fun but also could be a massive scope creep. Parking this for v3.", "tags": ["#mise", "#idea"]},
    {"title": "Mise performance issue fixed", "content": "Recipe search was crawling with 10k+ test recipes. Query was doing a full table scan on the ingredients JSONB column. Added a GIN index on the ingredients array and brought response time from 800ms to 40ms. Should have done this from the start but premature optimization blah blah.", "tags": ["#mise", "#work"]},
    {"title": "Mise recipe import working", "content": "The recipe URL importer is working! Tested with 20 popular food blogs and it successfully parsed 17 of them. The 3 failures were sites using non-standard markup. Added fallback heuristics for those - look for ingredient-like lists and instruction-like ordered lists. Good enough for launch.", "tags": ["#mise", "#work"]},
    {"title": "Mise nutritional data", "content": "Need to add nutritional data to Mise recipes. Looking at the USDA FoodData Central API - it's free and comprehensive. The challenge is mapping my parsed ingredients to their database entries. 'chicken breast' is straightforward but '2 handfuls of fresh spinach' is... less so.", "tags": ["#mise", "#api"]},
    {"title": "Mise deployment plan", "content": "Mise deployment plan: Railway for the API server (easy Postgres, good free tier), Vercel for the web frontend, and eventually React Native for mobile. Keeping it simple. No Kubernetes, no microservices, just a monolith that works. Can always break it up later if it takes off.", "tags": ["#mise", "#work"]},
    {"title": "Thinking about Mise monetization", "content": "How would Mise make money? Premium features: meal planning, nutritional tracking, advanced search filters. Or a 'pro' tier for food bloggers who want to host their recipes with nice formatting. Freemium model. Not thinking about this seriously yet but it's fun to daydream.", "tags": ["#mise", "#career"]},
    {"title": "Mise code review feedback", "content": "Got code review feedback on the recipe parser from a friend who's a senior dev. Main points: need better error handling for malformed ingredient strings (currently crashes on 'salt to taste'), should extract the parser into its own package for testing, and my regex is 'heroically unreadable'. Fair on all counts.", "tags": ["#mise", "#code-review"]},
]

WORK_JOB = [
    {"title": "Sprint planning notes", "content": "Sprint planning: 3 stories this week. Migration to the new auth provider, dashboard performance fixes, and the CSV export feature that's been in the backlog for 2 months. Feeling okay about scope. The auth migration is the risky one - touching every API endpoint.", "tags": ["#work", "#meetings"]},
    {"title": "Sprint retro thoughts", "content": "Sprint retro: we shipped everything but the CSV export got descoped again. Third sprint in a row. Starting to think nobody actually wants this feature and we just keep carrying it forward out of guilt. Going to propose we kill it next planning.", "tags": ["#work", "#meetings"]},
    {"title": "Standup was brutal today", "content": "Got unreasonably frustrated at standup today. Marcus asked me to explain my PR for the third time and I just... lost patience. Need to sit with that. He's not trying to be difficult, he just processes differently. I should have offered to do a screen share instead of getting snippy.", "tags": ["#work", "#reflection"]},
    {"title": "Context switching is killing me", "content": "Had 4 meetings today scattered across the day in a way that made deep work impossible. 9am standup, 11am design review, 2pm 1:1, 4pm sprint review. Each one is only 30 min but the context switching tax is brutal. Need to talk to my manager about meeting-free blocks.", "tags": ["#work", "#adhd"]},
    {"title": "Good code review session", "content": "Really productive code review session with Priya today. She caught a race condition in my websocket handler that would have been a nightmare in production. I caught a missing index on her new table that would have slowed queries. This is what code review should be.", "tags": ["#work", "#code-review"]},
    {"title": "Production incident", "content": "Production went down for 12 minutes today. A bad migration locked the users table. The rollback worked but it was scary. We need better migration testing. I'm going to propose a staging environment that runs migrations against a copy of prod data before we deploy.", "tags": ["#work", "#work"]},
    {"title": "Day job frustrations", "content": "Starting to feel the golden handcuffs at work. The work isn't bad, the people are great, but I'm not growing. Same CRUD endpoints, same React dashboards. Meanwhile Mise is the most exciting thing I've coded in years. But Mise doesn't pay rent.", "tags": ["#work", "#career"]},
    {"title": "1:1 with manager", "content": "1:1 with Sarah today. Brought up wanting more challenging work. She mentioned a potential ML project for recipe recommendations (ironic given Mise). Also discussed promotion timeline - probably Q3 if I lead the auth migration well. That's motivating.", "tags": ["#work", "#career"]},
    {"title": "Backlog grooming", "content": "Backlog grooming: 47 items. Archived everything older than 3 months that nobody's mentioned. Down to 28. Should have done this weeks ago. Digital clutter is just as draining as physical clutter.", "tags": ["#work", "#meetings"]},
    {"title": "Interview prep thought", "content": "Got a LinkedIn message from a recruiter at a food tech startup. Interesting because of the Mise overlap. Not seriously considering it but maybe I should do the call? Even if just for practice and market intel. Haven't interviewed in 2 years.", "tags": ["#work", "#career"]},
    {"title": "Work from home productivity", "content": "Working from home today and I'm flying. No interruptions, no 'quick questions', no overhearing conversations. Got through my entire sprint backlog by 2pm. Why do we go to the office again?", "tags": ["#work", "#adhd"]},
    {"title": "The open office problem", "content": "Someone brought their kid to the office today. Cute kid but the noise was impossible to work through. Even with noise cancelling headphones. I need to look into those loop earplugs everyone's talking about. Or just WFH more.", "tags": ["#work", "#adhd"]},
    {"title": "Deployment automation win", "content": "Set up GitHub Actions for auto-deployment to staging. Took most of the afternoon but now every PR gets a preview environment. Should have done this months ago. The dopamine hit of watching the green checkmarks cascade is unreasonable.", "tags": ["#work", "#wins"]},
    {"title": "Pair programming session", "content": "Pair programmed with the new junior dev for 2 hours. Exhausting but rewarding. Explained our auth flow, database schema, and deployment pipeline. She asked really good questions. Teaching forces you to actually understand your own codebase.", "tags": ["#work", "#work"]},
    {"title": "Tech debt frustration", "content": "Tried to add a simple feature today and got blocked by tech debt from 18 months ago. The user service has 3 different ways to look up a user depending on which file you're in. Spent 2 hours refactoring before I could even start on the actual feature. This is why we can't have nice things.", "tags": ["#work", "#work"]},
]

CERAMICS = [
    {"title": "First ceramics class", "content": "First ceramics class today! Learned about wedging clay to remove air bubbles. My hands are covered in slip and I love it. The instructor, Maria, says centering on the wheel is the hardest part for beginners. She's been doing this for 30 years and makes it look effortless. I could not center to save my life.", "tags": ["#ceramics", "#learning"]},
    {"title": "Centering practice", "content": "Spent the whole class just trying to center clay on the wheel. You push in and up, in and up, keeping your elbows braced against your body. The clay needs to spin perfectly true before you can open it. I got close twice but then my hand slipped and the whole thing went wonky. Maria says it takes most people 3-4 sessions. Patience.", "tags": ["#ceramics", "#learning"]},
    {"title": "First bowl on the wheel", "content": "THREW MY FIRST BOWL. It's lopsided, the walls are uneven, and there's a weird dimple where my thumb slipped. But I made it with my hands on a spinning wheel and it exists in the world now. The centering finally clicked today - it's about consistent pressure, not force. Taking it home to dry before bisque firing.", "tags": ["#ceramics", "#wins"]},
    {"title": "Trimming technique", "content": "Practiced trimming today. You flip the piece upside down on the wheel and carve away the excess from the bottom to create a foot ring. It's meditative - the ribbon of clay curling off the tool is so satisfying. Lost track of time completely. Maria said my trimming is better than my throwing, which is either a compliment or a burn.", "tags": ["#ceramics", "#learning"]},
    {"title": "Ceramics glazing day", "content": "Glazing day! Applied a celadon glaze to my bowl - three coats, letting each one dry before the next. The raw glaze looks chalky and nothing like the final color. Maria showed us how different thicknesses create different effects - thicker pools in recesses create darker tones. It's science meets art and I'm obsessed.", "tags": ["#ceramics", "#learning"]},
    {"title": "Bowl came out of the kiln", "content": "My bowl came out of the kiln and it's GORGEOUS. The celadon glaze turned that perfect jade green, pooling darker in the trimming lines. There's a tiny crack on the lip where the clay was too thin. But honestly it adds character. I keep picking it up and looking at it. Made this. With my hands. On a wheel.", "tags": ["#ceramics", "#wins"]},
    {"title": "Kiln temperature science", "content": "Deep dive into kiln temperatures today. Cone 6 (about 2230F) is mid-range - good for functional pottery. Cone 10 (2380F) is high-fire stoneware. The difference matters because glazes formulated for one temperature won't work at another. The silica and alumina ratios change how the glaze melts and flows. This is basically chemistry and I'm here for it.", "tags": ["#ceramics", "#learning"]},
    {"title": "Mug set project", "content": "Started a set of 4 matching mugs. Making matching pieces is SO much harder than single items. Getting consistent wall thickness, height, and rim diameter across all four requires measuring everything. Finished 2 today that are pretty close. Will do the other 2 next week.", "tags": ["#ceramics", "#learning"]},
    {"title": "Sgraffito technique", "content": "Tried sgraffito today - you coat the piece in colored slip (liquid clay) and then scratch through it to reveal the lighter clay underneath. Did a simple leaf pattern on a small plate. The lines are a bit shaky but the contrast is beautiful. Want to try more complex designs next time.", "tags": ["#ceramics", "#learning"]},
    {"title": "Centering is automatic now", "content": "Realized today I can center clay in about 30 seconds without thinking about it. Three months ago it took me 5 minutes of struggle. Muscle memory is real. Maria noticed and said I'm ready to start on taller forms - cylinders and vases. Exciting and terrifying.", "tags": ["#ceramics", "#wins"]},
    {"title": "Teapot project started", "content": "Started the most ambitious piece yet: a teapot. The body is thrown, but the spout and handle are separate pieces that get attached when everything is leather-hard. The tricky part is matching the dryness - if the body is drier than the spout, the joint will crack. Maria says teapots are the true test of a potter.", "tags": ["#ceramics", "#learning"]},
    {"title": "Glaze chemistry rabbit hole", "content": "Wait it's 2am? I've been reading about glaze chemistry for 4 hours. Started with a simple question about why my ash glaze came out matte instead of glossy and ended up deep in Seger unity formulas and alumina:silica ratios. The rabbit hole is real. But now I understand WHY glazes do what they do.", "tags": ["#ceramics", "#hyperfocus"]},
    {"title": "Studio time meditation", "content": "Saturday morning at the studio is becoming my favorite part of the week. Three hours with clay, no phone, no screens. The wheel demands presence - you can't think about work or scroll while centering. It's the closest thing to meditation I've found that actually works for my brain.", "tags": ["#ceramics", "#reflection"]},
    {"title": "Ceramics community", "content": "The ceramics studio community is so wholesome. Everyone shares glazes, helps clean up, celebrates each other's pieces. Met a retired teacher who's been throwing for 20 years and she gave me a bag of her custom glaze materials. No tech bro energy. Just people making things with their hands.", "tags": ["#ceramics", "#social"]},
    {"title": "Handmade tiles for kitchen?", "content": "Wait. What if I made the kitchen backsplash tiles MYSELF in ceramics class? I'm good enough at slab-building now. Could make 4x4 tiles, glaze them in a cohesive palette. It would take months but how cool would that be? Handmade tiles in my own kitchen. Need to ask Maria about the right clay body for tiles.", "tags": ["#ceramics", "#apartment"]},
]

LEARNING_OTHER = [
    {"title": "Four Thousand Weeks - key insight", "content": "Reading 'Four Thousand Weeks' by Burkeman and this line hit hard: 'The problem isn't that you don't have enough time. It's that you implicitly believe you should be able to do everything.' As someone with ADHD who has 47 half-started projects, this is painfully accurate. You have to choose what to neglect.", "tags": ["#reading", "#reflection"]},
    {"title": "Thinking in Systems notes", "content": "Started 'Thinking in Systems' by Donella Meadows. The idea of stocks and flows is clicking. A bathtub: the stock is water level, inflow is the faucet, outflow is the drain. Simple but powerful. Makes me think about my note-taking system as a stock with capture as inflow and processing as outflow.", "tags": ["#reading", "#learning"]},
    {"title": "Project Hail Mary - no spoilers", "content": "Staying up way too late reading Project Hail Mary. No spoilers but the science is incredible and the humor is perfect. Weir does this thing where he makes you learn orbital mechanics without realizing you're learning. 50 pages left and I don't want it to end.", "tags": ["#reading", "#hyperfocus"]},
    {"title": "Huberman Lab podcast notes", "content": "Huberman Lab episode on dopamine and motivation. Key takeaways: dopamine is about anticipation not reward, variable reward schedules are the most addictive (hello social media), and you can 'reset' your dopamine baseline with deliberate cold exposure or exercise. The cold shower thing actually has science behind it.", "tags": ["#podcast", "#learning"]},
    {"title": "Acquired podcast - LVMH episode", "content": "Acquired episode on LVMH was fascinating. Bernard Arnault built the luxury empire by understanding that scarcity creates desire. Relevant to product design - sometimes removing features makes a product more desirable. Less is more if the 'less' is curated.", "tags": ["#podcast", "#learning"]},
    {"title": "Kubernetes attempt #4", "content": "Restarted the Kubernetes course again. This is attempt number... 4? Made it through pods and deployments before my attention wandered. The problem is I don't have a real use case - I'm learning it because I 'should' not because I need it. Maybe I should just admit Kubernetes isn't for me right now.", "tags": ["#kubernetes", "#learning"]},
    {"title": "Kubernetes services and ingress", "content": "Actually made progress on Kubernetes today! Got through Services, Ingress, and ConfigMaps. Having a real project to deploy (Mise) makes it way more concrete. Set up a local minikube cluster and got the API server running in a pod. It works! The YAML is still hell though.", "tags": ["#kubernetes", "#learning"]},
    {"title": "Kubernetes frustration", "content": "Haven't touched the Kubernetes course in 3 weeks. Who am I kidding. Every time I open it I feel this weight of guilt that I haven't kept up. The ironic thing is the guilt makes it harder to start. Classic ADHD avoidance spiral. Maybe I should just delete the course and stop pretending.", "tags": ["#kubernetes", "#adhd"]},
    {"title": "Lex Fridman interview notes", "content": "Lex Fridman interview with a ceramicist/materials scientist. She talked about how the atomic structure of clay determines its plasticity. Bentonite has tiny plate-shaped particles that slide over each other when wet. That's why it feels so smooth on the wheel. The intersection of science and craft is endlessly fascinating.", "tags": ["#podcast", "#ceramics"]},
    {"title": "Thinking in Systems - feedback loops", "content": "Meadows on feedback loops: 'A reinforcing loop can be a virtuous circle or a vicious circle.' My exercise habit is a virtuous circle - exercise improves sleep, better sleep improves focus, better focus means I get to the gym. My doom-scrolling is the vicious one. Need to identify which loops I'm feeding.", "tags": ["#reading", "#reflection"]},
    {"title": "Finished Four Thousand Weeks", "content": "Finished 'Four Thousand Weeks'. The ending chapter about cosmic insignificance sounds depressing but it's actually freeing. If nothing I do matters on a cosmic scale, then I'm free to do what matters to ME. Ceramics matters. Mise matters. Kubernetes... maybe doesn't matter to me and that's fine.", "tags": ["#reading", "#reflection"]},
    {"title": "Kubernetes - gave myself permission to pause", "content": "Following up on that Burkeman insight - I'm officially pausing Kubernetes. Not quitting, pausing. I have finite attention and right now Mise and ceramics are where my energy wants to go. If I need K8s for Mise deployment later, that'll be the motivation. Forced learning without purpose doesn't stick.", "tags": ["#kubernetes", "#reflection"]},
]

HEALTH_ADHD = [
    {"title": "Medication timing experiment", "content": "Talked to Dr. Chen about Vyvanse timing. Moving my dose from 8am to 7:30am to see if it kicks in before my 9am standup. The 30-minute gap where it hasn't hit yet but I need to be functional is rough. She also suggested taking it with protein for slower absorption and fewer crashes.", "tags": ["#adhd", "#medication"]},
    {"title": "Vyvanse effectiveness window", "content": "Tracking my Vyvanse effectiveness: kicks in around 45 min after taking it, peak focus 2-4 hours in (so 9:30am-11:30am), slow taper starting around 2pm, noticeable drop by 4pm. My best work window is 10am-12pm. Need to protect that window ruthlessly - no meetings.", "tags": ["#adhd", "#medication"]},
    {"title": "ADHD productivity observation", "content": "I notice I'm most productive between 10am and 1pm. After lunch there's a crash that nothing fixes - not coffee, not a walk, not medication boosters. Afternoons are for meetings, email, and low-stakes tasks. Mornings are for code. Stop fighting this.", "tags": ["#adhd", "#reflection"]},
    {"title": "Body doubling works", "content": "ADHD win: used body doubling on a video call with Maya and powered through my entire to-do list in 2 hours. Having someone else just... present... while working makes an absurd difference. Need to do this more often. Maybe there's a body doubling app? Should look into that.", "tags": ["#adhd", "#wins"]},
    {"title": "Task initiation struggle", "content": "Struggling with task initiation today. Everything feels equally important and urgent and I can't pick where to start. The to-do list is mocking me. Going to try the 2-minute rule - just do the thing that takes less than 2 minutes and let momentum build from there.", "tags": ["#adhd", "#reflection"]},
    {"title": "Hyperfocus is not a superpower", "content": "People keep calling hyperfocus an 'ADHD superpower' and it drives me crazy. Yes I can code for 6 hours straight without eating, but I ALSO can't stop when I need to, I miss appointments, and I crash hard after. It's not a superpower, it's a lack of self-regulation that sometimes happens to align with productivity.", "tags": ["#adhd", "#reflection"]},
    {"title": "Executive function and dishes", "content": "ADHD realization: my 'laziness' with dishes isn't laziness. It's executive function. The task has multiple invisible steps (clear counter, fill sink, scrub, rinse, dry, put away) and my brain can't sequence them without effort. Broke it into a 3-step routine with a specific order. Way easier now.", "tags": ["#adhd", "#wins"]},
    {"title": "The pomodoro problem", "content": "The pomodoro technique is not working for me. 25 minutes is too short when I'm in flow (the timer breaks hyperfocus) and too long when I'm stuck (I'm just staring at the screen for 25 min). Trying flexible intervals instead - work until a natural break point, then consciously decide to continue or stop.", "tags": ["#adhd", "#reflection"]},
    {"title": "Great ADHD day", "content": "Amazing day. Started medication on time, did my full morning routine (breakfast, journal, walk), got through 3 deep work sessions, went bouldering, cooked dinner. What made today different? I think it was the morning walk - 15 min outside before screens. Going to try replicating this tomorrow.", "tags": ["#adhd", "#wins"]},
    {"title": "Doom scrolling pattern", "content": "Noticed I've been doom scrolling more this week. Phone screen time is up to 4.5 hours. Usually a sign of understimulation - my brain is seeking easy dopamine because work isn't providing enough challenge. Need more creative projects or harder problems to chew on.", "tags": ["#adhd", "#reflection"]},
    {"title": "Therapy session - shame spiral", "content": "Therapy today: worked on the shame spiral around unfinished projects. My therapist pointed out that starting many things isn't failure, it's exploration. The shame comes from neurotypical expectations about 'finishing what you start.' Some projects are meant to be experiments, not commitments.", "tags": ["#therapy", "#adhd"]},
    {"title": "Medication crash afternoon", "content": "Vyvanse crash hit hard at 3pm today. Went from productive and focused to foggy and irritable in about 20 minutes. Ate some protein and went for a short walk which helped slightly. Dr. Chen mentioned a small IR booster for afternoons but I'm hesitant to add more stimulants.", "tags": ["#adhd", "#medication"]},
    {"title": "ADHD tax is real", "content": "The ADHD tax this month: $45 late fee on a bill I forgot to pay (it was sitting on my desk, opened, with a sticky note saying PAY THIS), $30 on duplicate groceries because I forgot what was in the fridge, and 2 hours rebuilding a spreadsheet I accidentally deleted. Automation is self-care.", "tags": ["#adhd", "#reflection"]},
    {"title": "Compensation strategies working", "content": "My compensation strategies are actually working: everything goes in the calendar with alerts, bills are on auto-pay, keys have a Tile tracker, meds are in a weekly pill organizer by the coffee maker. It took years to build these systems but they're invisible now. Past me did future me a huge favor.", "tags": ["#adhd", "#wins"]},
    {"title": "CBT homework - thought record", "content": "CBT homework: thought record for the guilt about not working on Mise this week. Automatic thought: 'I'm wasting time and the app will never launch.' Evidence for: haven't coded in 5 days. Evidence against: I was sick for 3 of those days, and I've been consistently working on it for months. Balanced thought: 'A few days off doesn't erase months of progress.'", "tags": ["#therapy", "#adhd"]},
]

HEALTH_EXERCISE = [
    {"title": "Morning run", "content": "Morning run: 3 miles in 28 minutes. Legs felt heavy from bouldering yesterday but my mind was clear after. Running is the best ADHD medication that isn't medication.", "tags": ["#exercise"]},
    {"title": "Bouldering session - V4 send", "content": "SENT MY FIRST V4! The purple problem on the overhang wall. Been projecting it for 3 weeks. The crux is a heel hook into a dynamic move to a sloper. My forearms are destroyed but I'm grinning. Progress in climbing is so tangible - either you send or you don't.", "tags": ["#bouldering", "#wins"]},
    {"title": "Bouldering plateau", "content": "Feeling stuck at the V3/V4 boundary in bouldering. I can flash most V3s but V4s take me weeks. I think my finger strength is the bottleneck. Looking into a hangboard routine but need to be careful about tendon injuries. Tendons adapt slower than muscles.", "tags": ["#bouldering", "#exercise"]},
    {"title": "Yoga attempt", "content": "Tried a 20-minute yoga video on YouTube. The breathing exercises helped with anxiety more than I expected. The actual poses were hard - my flexibility is terrible from sitting at a desk all day. Going to try 3x/week and see if it helps with the bouldering too.", "tags": ["#exercise"]},
    {"title": "Gym accountability", "content": "Gym consistency check: 3x/week for the last month. Monday bouldering, Wednesday run, Saturday bouldering. The key is going even when I don't feel like it. The hardest part is putting on shoes and leaving the house - once I'm there, I always have a good session.", "tags": ["#exercise", "#wins"]},
    {"title": "New running route", "content": "Tried a new running route through Griffith Park. 4 miles with some hills. Saw a coyote just chilling by the trail. The elevation gain is good training and the views of the city from the top are worth the extra effort. Making this my regular weekend route.", "tags": ["#exercise"]},
    {"title": "Rest day guilt", "content": "Taking a rest day and feeling guilty about it. My body needs it - my fingers are still sore from Tuesday's bouldering session. But my brain is telling me I'm being lazy. Reminding myself that rest IS part of training. Muscles grow during recovery, not during the workout.", "tags": ["#exercise", "#adhd"]},
    {"title": "Bouldering technique insight", "content": "Bouldering insight from watching better climbers: I'm using too much upper body. Good climbers push with their legs and use arms mainly for balance. Tried focusing on footwork today and suddenly V3s felt easy. It's not about strength, it's about technique. Same lesson as centering clay.", "tags": ["#bouldering", "#learning"]},
]

HEALTH_SLEEP = [
    {"title": "Sleep tracking this week", "content": "Sleep tracking: averaged 6.5 hours this week. Not great. The main issue is getting to bed - I keep telling myself 'one more episode' or 'let me just finish this section.' Going to try the no screens after 9pm rule again. Last time it helped a lot.", "tags": ["#sleep", "#health"]},
    {"title": "3am wake up again", "content": "Woke up at 3am again. Brain immediately started running through the Mise feature backlog and then somehow pivoted to worrying about whether the Joshua Tree campsite has cell service. Tried the breathing technique from therapy (4-7-8 pattern) and fell back asleep around 4:30.", "tags": ["#sleep"]},
    {"title": "Sleep experiment - no screens", "content": "Day 3 of no screens after 9pm. Reading physical books instead. Fell asleep at 10:30 last night which is basically a miracle. The hardest part is the first 30 minutes after putting down the phone - there's an actual physical craving to check it.", "tags": ["#sleep", "#health"]},
    {"title": "Terrible sleep - hyperfocus", "content": "Terrible sleep last night. Hyperfocused on a ceramics technique video that led to glaze chemistry articles that led to a materials science rabbit hole. Looked up and it was 2am. The YouTube autoplay algorithm is literally designed to exploit hyperfocus. Deleted the app from my phone.", "tags": ["#sleep", "#adhd"]},
    {"title": "Sleep improving with routine", "content": "Sleep has been consistently better since I started the 'wind down' routine: 9pm screens off, make tomorrow's to-do list (gets the thoughts out of my head), read for 20 min, lights out by 10. Averaging 7.5 hours this week. The to-do list part is key - it stops the 3am planning sessions.", "tags": ["#sleep", "#wins"]},
    {"title": "Melatonin experiment", "content": "Tried 0.5mg melatonin for the first time. Lower dose than what's sold in stores (most are 5-10mg which is way too much according to Huberman). Fell asleep faster but had weird vivid dreams. Going to try it for a week and track the results.", "tags": ["#sleep", "#health"]},
    {"title": "Weekend sleep debt", "content": "Slept 10 hours on Saturday. Body clearly needed it after averaging 6 hours all week. I know sleep debt isn't fully repayable but the difference in how I feel today is dramatic. Clearer head, better mood, actually want to do things instead of just existing.", "tags": ["#sleep", "#health"]},
    {"title": "Insomnia and work stress", "content": "Can't sleep. Brain is replaying the production incident from today on loop. 'What if the rollback hadn't worked? What if we'd lost data?' Logically I know it's fine but my nervous system hasn't gotten the memo. Going to try writing down the worry and then physically closing the notebook.", "tags": ["#sleep", "#work"]},
    {"title": "Blue light glasses review", "content": "Got blue light blocking glasses. Jury's still out on whether they actually help with sleep but they definitely reduce the eye strain I feel after 8 hours of screen time. Placebo or not, I'm keeping them.", "tags": ["#sleep", "#health"]},
    {"title": "Caffeine cutoff experiment", "content": "Moved my caffeine cutoff from 2pm to 12pm. It's been 5 days and I think I'm falling asleep faster? Hard to isolate variables though since I also started the wind-down routine the same week. Either way, something is working. Don't fix what ain't broke.", "tags": ["#sleep", "#health"]},
]

PERSONAL_JOSHUA_TREE = [
    {"title": "Joshua Tree trip idea", "content": "Starting to plan a camping trip to Joshua Tree. February would be perfect - not too hot, not too cold. Need to check campsite availability. Jumbo Rocks looks amazing from photos. Going to text the group chat and see who's interested.", "tags": ["#joshua-tree", "#social"]},
    {"title": "Joshua Tree campsite research", "content": "Campsite research: Jumbo Rocks is the most popular (stunning boulder formations) but books up fast. Indian Cove is more secluded and has the advantage of being first-come-first-served. Black Rock has actual flush toilets which... matters more than I'd like to admit. Leaning toward Jumbo Rocks if I can get a reservation.", "tags": ["#joshua-tree"]},
    {"title": "Joshua Tree - group confirmed", "content": "Joshua Tree crew confirmed: me, Sarah, Marcus (from work), and his partner Jamie. Four people, two tents. Sarah's bringing her car with the roof rack for gear. February 14-16 long weekend. Just booked Jumbo Rocks site #47!", "tags": ["#joshua-tree", "#social"]},
    {"title": "Camping gear checklist", "content": "Gear check for Joshua Tree: tent (good), sleeping bag rated to 30F (good), sleeping pad (need to repair the valve), headlamp (batteries dead, need new ones), camp stove (borrowed from Sarah last time, need to buy my own). Making a proper checklist instead of my usual 'throw stuff in the car' approach.", "tags": ["#joshua-tree", "#todo"]},
    {"title": "Joshua Tree meal planning", "content": "Camp meal plan: Night 1 is foil packet dinners (easy after the drive). Night 2 is camp stove stir fry - prepping ingredients at home and bringing them in a cooler. Breakfasts are oatmeal with banana and peanut butter. Snacks: trail mix, jerky, oranges. Mise recipe app would be perfect for this...", "tags": ["#joshua-tree", "#cooking"]},
    {"title": "Joshua Tree hiking research", "content": "Joshua Tree hikes shortlist: Ryan Mountain (3 miles, panoramic views, moderate), Hidden Valley (1 mile, easy, cool rock formations), Skull Rock loop (1.7 miles, easy, iconic). Doing Ryan Mountain Saturday morning when it's cool, easy ones in the afternoon. Don't want to overdo it.", "tags": ["#joshua-tree"]},
    {"title": "Bought a camp stove", "content": "Bought a Jetboil Flash camp stove. It boils water in 100 seconds which feels like cheating. Also got a proper headlamp (Black Diamond Spot 400) because my old one was basically a candle. Joshua Tree gear is coming together.", "tags": ["#joshua-tree", "#todo"]},
    {"title": "Joshua Tree update - Sarah's car", "content": "Joshua Tree planning update: Sarah confirmed she can drive. Her Subaru fits all the gear and 4 people comfortably. Marcus is handling the firewood (no collecting in the park). I'm on food and water. Jamie's bringing a telescope for stargazing. This trip is going to be amazing.", "tags": ["#joshua-tree", "#social"]},
    {"title": "Desert night sky anticipation", "content": "One thing I'm most excited about for Joshua Tree: the night sky. Bortle class 2 - basically zero light pollution. Jamie's telescope should show galaxies. I've never seen the Milky Way clearly. Growing up in the city, I didn't even know you COULD see it with naked eyes.", "tags": ["#joshua-tree", "#reflection"]},
    {"title": "Joshua Tree - weather check", "content": "Checked the weather for Joshua Tree next weekend: highs around 65F, lows around 40F, no rain. Perfect camping weather. Need to remember extra blankets though - desert nights get cold fast. Also sunscreen for the hikes even though it doesn't feel hot.", "tags": ["#joshua-tree"]},
    {"title": "Post-camping reflection", "content": "Back from Joshua Tree and I'm still buzzing. The stars were unreal - Jamie's telescope showed us the Orion Nebula and it was this fuzzy glowing cloud and I almost cried? The hike up Ryan Mountain at sunrise was worth the early alarm. Something about being in the desert strips away the noise. Need to do this more.", "tags": ["#joshua-tree", "#reflection"]},
    {"title": "Joshua Tree photos", "content": "Going through Joshua Tree photos. Got some incredible ones of the rock formations at golden hour. Marcus captured a shot of all four of us silhouetted against the sunset that's going to be framed. Already talking about the next trip - maybe Anza-Borrego in spring for the wildflower bloom.", "tags": ["#joshua-tree", "#social"]},
]

PERSONAL_APARTMENT = [
    {"title": "Kitchen backsplash planning", "content": "Want to redo the kitchen backsplash. The builder-grade white subway tile is fine but boring. Thinking about something with more personality - handmade tiles with slight variations in color and texture. Zellige tiles from Morocco are beautiful but expensive ($20/sq ft). Maybe I could make my own in ceramics class?", "tags": ["#apartment"]},
    {"title": "Backsplash measurements", "content": "Measured the kitchen backsplash area: 24 square feet. At $15-20/sq ft for nice tiles plus installation, that's $500-700 total. If I make tiles myself in ceramics class, it's basically free (studio membership covers materials). The trade-off is time - probably 2 months of weekend work.", "tags": ["#apartment"]},
    {"title": "Bedroom paint colors", "content": "Looked at paint colors for the bedroom. Currently it's the landlord-special beige. Leaning toward 'Quiet Moments' by Benjamin Moore (soft blue-green) or 'Swiss Coffee' (warm white) with a sage green accent wall. Need to get samples and test them against the furniture.", "tags": ["#apartment"]},
    {"title": "Floating shelves installed", "content": "Installed the floating shelves in the living room! Took 3 hours including 45 minutes of finding studs (the hard part). They're perfectly level, which is satisfying given my track record with DIY. Stained them walnut to match the coffee table. Already have too many things to put on them.", "tags": ["#apartment", "#wins"]},
    {"title": "Renovation budget", "content": "Renovation budget reality check: backsplash $500-700, paint supplies $150, new shelving (done) $120, bathroom mirror replacement $80. Total about $1000-1050. That's reasonable if I spread it over 3 months. Backsplash is the big one - saving that for last.", "tags": ["#apartment"]},
    {"title": "Backsplash tile samples", "content": "Got tile samples from 3 different suppliers. The Moroccan zellige is stunning in person but the irregularity might drive me crazy during installation. The Japanese wabi-sabi tiles are gorgeous and more uniform. And there's a local ceramicist selling handmade tiles for $12/sq ft. Need to decide.", "tags": ["#apartment"]},
    {"title": "Paint test patches", "content": "Put up paint test patches in the bedroom. 'Quiet Moments' looks great in morning light but kind of depressing in the evening under artificial light. 'Swiss Coffee' is safe but boring. The sage accent wall is the clear winner - warm, calming, and looks good at all times of day. Going with that.", "tags": ["#apartment"]},
    {"title": "Bedroom painted", "content": "Painted the bedroom accent wall! Sage green and it looks incredible. The rest of the walls are Swiss Coffee for contrast. Took all of Saturday but the transformation is dramatic. My bedroom finally feels like a space I curated intentionally instead of just existing in.", "tags": ["#apartment", "#wins"]},
]

PERSONAL_SOCIAL = [
    {"title": "Game night with friends", "content": "Game night at Sam's place. Played Codenames and Wingspan. I dominated Wingspan (the birder in me emerged) but was terrible at Codenames because I kept giving overly abstract clues. 'Galaxy, 3' for 'Milky Way, Star, Space' made sense to me but nobody else. ADHD brain makes weird connections.", "tags": ["#social"]},
    {"title": "Dinner with Sam and Jordan", "content": "Dinner with Sam and Jordan tonight. Sam is thinking about starting a pottery business - selling mugs and bowls at farmers markets. We talked about the parallels between ceramics and software craftsmanship. Both are about iteration, both have this gap between what you envision and what your hands produce.", "tags": ["#social", "#ceramics"]},
    {"title": "Mom's birthday gift", "content": "Mom's birthday next weekend. She mentioned wanting to learn watercolor painting. Getting her a beginner watercolor set with good brushes and a Skillshare subscription. Also going to make her a small ceramic bowl from class. Handmade gifts hit different.", "tags": ["#social", "#todo"]},
    {"title": "Concert tonight", "content": "Going to see Japanese Breakfast at the Greek Theatre tonight. Haven't been to a live show in months. I always forget how much I love live music until I'm there. The energy of a crowd collectively experiencing something beautiful - it's irreplaceable.", "tags": ["#social"]},
    {"title": "Cancelled plans guilt", "content": "Cancelled plans with Mira tonight. I just... can't. Social battery is at 0 after a week of back-to-back meetings at work. Texted an honest explanation instead of making a fake excuse. She was understanding. Need to be better about not overcommitting socially. Quality over quantity.", "tags": ["#social", "#adhd"]},
    {"title": "Friend's career advice", "content": "Long conversation with Jordan about the job situation. She left her corporate gig to freelance 2 years ago and doesn't regret it. But she also said the first 6 months were terrifying. 'You need a financial cushion and you need to be honest about your risk tolerance.' Solid advice.", "tags": ["#social", "#career"]},
]

RANDOM_THOUGHTS = [
    {"title": "Shower thought on flow and hyperfocus", "content": "Shower thought: the overlap between ADHD hyperfocus and 'flow state' is interesting. Flow is chosen and controllable - you can exit when you need to. Hyperfocus happens TO you and is hard to break. Same neurochemistry, different degree of agency.", "tags": ["#reflection"]},
    {"title": "Digital minimalism idea", "content": "What if I only kept apps on my phone that I used in the last 7 days? My phone would have like 8 apps. Messages, maps, camera, Spotify, bank, Uber, weather, and... that's it. All the others are dopamine traps I open out of habit not need.", "tags": ["#idea", "#adhd"]},
    {"title": "Productive procrastination", "content": "The concept of 'productive procrastination': avoiding one task by doing another useful task. Today I reorganized my entire bookshelf instead of writing the Mise API docs. Is that a bug or a feature? The bookshelf looks great.", "tags": ["#reflection", "#adhd"]},
    {"title": "Best ideas before sleep", "content": "Why do I always have my best ideas right before falling asleep? Tonight's 11pm revelation: Mise should have a 'cook with what you have' mode where you photograph your fridge and it suggests recipes. Computer vision + ingredient matching. Writing this down before I forget. Sleep can wait 5 more minutes.", "tags": ["#idea", "#mise"]},
    {"title": "Coffee shop productivity", "content": "Worked from a coffee shop today and was 3x more productive than at home. The ambient noise, the social contract of being in public, the lack of a couch to collapse on. Maybe I should get a coworking membership instead of pretending my apartment is an office.", "tags": ["#reflection", "#adhd"]},
    {"title": "Spice organization system", "content": "Random observation: I organize my kitchen spices alphabetically but my books by color. My tools by frequency of use but my clothes by season. There's no consistent system and yet I know where everything is. Maybe organization is personal and the 'right' system is whatever lets YOU find things.", "tags": ["#reflection"]},
    {"title": "Dune Part Two reaction", "content": "Just watched Dune Part Two. The sound design is INSANE - the thumpers, the sandworm rumble, that throat singing in the Fremen scenes. Villeneuve understands that sci-fi is about making you FEEL a different world, not just see it. Need to watch it again with better speakers.", "tags": ["#reflection"]},
    {"title": "Severance season 2 thoughts", "content": "Severance season 2 is messing with my head. The work-life separation metaphor is so relevant. Sometimes I feel like I have an 'innie' who does corporate work and an 'outie' who makes pottery and builds recipe apps. The show asks: which one is the real you?", "tags": ["#reflection"]},
    {"title": "LA observation", "content": "LA thing: spent 45 minutes driving 6 miles to a restaurant. Ate in 30 minutes. Spent 45 minutes driving back. The food was incredible but the math doesn't math. This city is beautiful and absurd in equal measure.", "tags": ["#reflection"]},
    {"title": "Sunset from apartment", "content": "The sunset from my apartment balcony tonight was unreal. Pink and orange and purple like a bad Photoshop that's actually real. Sat there for 20 minutes just watching it change. More of this. Less doomscrolling.", "tags": ["#reflection"]},
    {"title": "Restaurant rec - Jitlada", "content": "Restaurant discovery: Jitlada in Thai Town. Southern Thai food that's genuinely spicy. The crispy morning glory is life-changing. If Mise ever needs test data for Thai cuisine, I know where to go for research. Tax-deductible dinner?", "tags": ["#cooking"]},
    {"title": "The attention economy", "content": "Read an article about the attention economy that connected a lot of dots. Every app on my phone is competing for the same limited resource: my attention. And I have ADHD, which means my attention is already a scarce commodity. I'm basically a whale in their casino.", "tags": ["#reading", "#adhd"]},
]

RANDOM_CAPTURES = [
    {"title": "Dentist appointment", "content": "Need to call the dentist for a cleaning. It's been... longer than I want to admit.", "tags": ["#todo"]},
    {"title": "Noise cancelling headphones", "content": "Look into noise cancelling headphones for the office. Sony XM5 or AirPods Max? Need to try both.", "tags": ["#todo"]},
    {"title": "Grocery list", "content": "Avocados, eggs, sourdough, oat milk, bananas, chicken thighs, broccoli, that fancy hot sauce from the farmers market (the green one with the rooster).", "tags": ["#todo", "#cooking"]},
    {"title": "Water plants before camping", "content": "Remember to water the plants before leaving for Joshua Tree. And ask the neighbor to check on them.", "tags": ["#todo", "#joshua-tree"]},
    {"title": "Ceramics book recommendation", "content": "Check if the library has 'The Art of Throwing' by Simon Leach. Sam said it changed how she thinks about form.", "tags": ["#todo", "#ceramics"]},
    {"title": "Cancel streaming service", "content": "Cancel the Peacock subscription I've been paying for since I watched that one show 4 months ago. ADHD tax.", "tags": ["#todo", "#adhd"]},
    {"title": "Return the shoes", "content": "Return the wrong-size running shoes before the 30-day window closes. They've been sitting by the door for 2 weeks.", "tags": ["#todo"]},
    {"title": "Car registration reminder", "content": "Car registration expires next month. Set a reminder because I WILL forget and then it's a fix-it ticket.", "tags": ["#todo"]},
    {"title": "Gift idea for Sarah", "content": "Sarah mentioned she wants to get into bouldering. Birthday is March 5. Get her a day pass + rental package at my climbing gym.", "tags": ["#todo", "#social"]},
    {"title": "Interesting word", "content": "Learned the word 'sonder' - the realization that each passerby has a life as vivid and complex as your own. There should be more words for these feelings.", "tags": ["#reflection"]},
    {"title": "Camping playlist", "content": "Make a camping playlist for Joshua Tree. Desert vibes: Khruangbin, Tame Impala, Tycho, Men I Trust. No lyrics for the stargazing portion.", "tags": ["#joshua-tree", "#todo"]},
    {"title": "Backup phone contacts", "content": "Backup phone contacts somewhere. If I lose this phone I lose everyone's number. When did we stop memorizing phone numbers?", "tags": ["#todo"]},
    {"title": "Browser tabs confession", "content": "Currently have 147 browser tabs open. That's not a number, that's a cry for help.", "tags": ["#adhd"]},
    {"title": "Mise name origin", "content": "Someone asked why I named the app 'Mise'. It's from 'mise en place' - the French culinary principle of having everything measured, cut, and ready before you start cooking. Organization as a precondition for creativity. Also it's short and the domain was available.", "tags": ["#mise"]},
    {"title": "Morning walk game changer", "content": "Two weeks into the morning walk habit and it's a game changer. 15 minutes, no phone, just walking. My brain goes from chaos to something resembling order by the time I'm home. It's like defragging a hard drive.", "tags": ["#health", "#wins"]},
]


# --- Timestamp Generation ---

def gen_timestamps(start_date, end_date, target_count):
    """Generate realistic timestamps with ADHD-like patterns."""
    timestamps = []
    current = start_date

    while current <= end_date:
        day_of_week = current.weekday()  # 0=Mon, 6=Sun
        is_weekday = day_of_week < 5

        # Determine note count for this day
        month_idx = (current - start_date).days / 30.0
        base_rate = 5.0 + month_idx * 1.0  # increasing trend

        # Holiday reductions
        month_day = (current.month, current.day)
        if month_day in [(11, 27), (11, 28), (12, 25), (12, 26), (12, 31), (1, 1)]:
            base_rate *= 0.3

        # Burst days (roughly every 10 days)
        day_offset = (current - start_date).days
        is_burst = (day_offset % 11 == 3) or (day_offset % 13 == 7)
        if is_burst:
            base_rate *= 1.8

        # Post-burst recovery
        is_recovery = (day_offset % 11 == 4) or (day_offset % 13 == 8)
        if is_recovery:
            base_rate *= 0.3

        count = max(0, int(random.gauss(base_rate, 1.5)))
        count = min(count, 10)

        for _ in range(count):
            if is_weekday:
                r = random.random()
                if r < 0.35:
                    hour = random.randint(9, 12)
                elif r < 0.6:
                    hour = random.randint(13, 17)
                elif r < 0.92:
                    hour = random.randint(18, 22)
                else:
                    hour = random.randint(23, 26) % 24  # late night
            else:
                r = random.random()
                if r < 0.15:
                    hour = random.randint(8, 9)  # ceramics morning
                elif r < 0.85:
                    hour = random.randint(10, 21)
                else:
                    hour = random.randint(22, 26) % 24

            minute = random.randint(0, 59)
            second = random.randint(0, 59)
            ts = current.replace(hour=hour % 24, minute=minute, second=second)
            timestamps.append(ts)

        current += timedelta(days=1)

    # Trim or pad to target
    if len(timestamps) > target_count:
        timestamps = sorted(random.sample(timestamps, target_count))

    timestamps.sort()
    return timestamps


def pick_note(timestamps_idx, total, pools_with_weights):
    """Pick a note from weighted pools based on position in timeline."""
    r = random.random()
    cumulative = 0
    for pool, weight in pools_with_weights:
        cumulative += weight
        if r < cumulative:
            return random.choice(pool)
    return random.choice(pools_with_weights[-1][0])


def format_timestamp(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%S-08:00")


def main():
    start = datetime(2025, 11, 15)
    end = datetime(2026, 2, 15)
    target = 560

    timestamps = gen_timestamps(start, end, target)

    # Build weighted pools
    pools = [
        (WORK_MISE, 0.12),
        (WORK_JOB, 0.18),
        (CERAMICS, 0.12),
        (LEARNING_OTHER, 0.08),
        (HEALTH_ADHD, 0.12),
        (HEALTH_EXERCISE, 0.06),
        (HEALTH_SLEEP, 0.08),
        (PERSONAL_JOSHUA_TREE, 0.06),
        (PERSONAL_APARTMENT, 0.05),
        (PERSONAL_SOCIAL, 0.04),
        (RANDOM_THOUGHTS, 0.05),
        (RANDOM_CAPTURES, 0.04),
    ]

    # Track usage to avoid too many repeats
    usage_count = {}

    notes = []
    for i, ts in enumerate(timestamps):
        month = ts.month
        day_of_week = ts.weekday()
        hour = ts.hour

        # Adjust weights by context
        adjusted_pools = []
        for pool, weight in pools:
            w = weight
            # More work during weekday work hours
            if pool in (WORK_MISE, WORK_JOB) and day_of_week < 5 and 9 <= hour <= 17:
                w *= 1.5
            # Less work on weekends
            if pool in (WORK_MISE, WORK_JOB) and day_of_week >= 5:
                w *= 0.3
            # More ceramics on Saturday mornings
            if pool == CERAMICS and day_of_week == 5 and hour < 13:
                w *= 2.0
            # More sleep notes late at night
            if pool == HEALTH_SLEEP and (hour >= 22 or hour <= 5):
                w *= 2.0
            # More Joshua Tree notes closer to Feb
            if pool == PERSONAL_JOSHUA_TREE and month >= 1:
                w *= 1.5
            # More exercise notes morning/evening
            if pool == HEALTH_EXERCISE and (6 <= hour <= 9 or 17 <= hour <= 20):
                w *= 1.5
            adjusted_pools.append((pool, w))

        # Normalize
        total_w = sum(w for _, w in adjusted_pools)
        adjusted_pools = [(p, w/total_w) for p, w in adjusted_pools]

        # Pick note
        note_template = pick_note(i, len(timestamps), adjusted_pools)

        # Track to reduce exact duplicates
        key = note_template["title"] + note_template["content"][:50]
        usage_count[key] = usage_count.get(key, 0) + 1

        # Add slight variation for repeated templates
        content = note_template["content"]
        if usage_count[key] > 1:
            # Add a prefix variation
            prefixes = [
                "Update: ", "Thinking more about this - ", "Following up: ",
                "Quick note - ", "Revisiting this thought: ", "Adding to earlier note - ",
                "More on this: ", "New development - ", "Realized something: ",
                "Late night thought: ", "Morning reflection: ", "Post-coffee clarity: ",
            ]
            content = random.choice(prefixes) + content[0].lower() + content[1:]

        notes.append({
            "title": note_template["title"],
            "content": content,
            "created_at": format_timestamp(ts),
            "tags": note_template["tags"],
        })

    # Write output
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    fixture_dir = os.path.join(project_root, "fixtures")
    os.makedirs(fixture_dir, exist_ok=True)

    output_path = os.path.join(fixture_dir, "dev-seed-notes.json")
    with open(output_path, "w") as f:
        json.dump(notes, f, indent=2)

    # Summary
    print(f"Generated {len(notes)} notes")
    print(f"Date range: {notes[0]['created_at']} to {notes[-1]['created_at']}")
    print(f"Output: {output_path}")

    # Domain breakdown
    tag_counts = {}
    for note in notes:
        for tag in note["tags"]:
            tag_counts[tag] = tag_counts.get(tag, 0) + 1

    print("\nTop tags:")
    for tag, count in sorted(tag_counts.items(), key=lambda x: -x[1])[:15]:
        print(f"  {tag}: {count}")

    # Monthly breakdown
    monthly = {}
    for note in notes:
        month_key = note["created_at"][:7]
        monthly[month_key] = monthly.get(month_key, 0) + 1

    print("\nMonthly distribution:")
    for month, count in sorted(monthly.items()):
        print(f"  {month}: {count}")


if __name__ == "__main__":
    main()

# post_tweet.R
# Post to X using rtweet
#
# Before running:
#   1. install.packages("rtweet")
#   2. Fill in your credentials below (or store them in .Renviron — see below)
#   3. Ensure your X app has "Read and Write" permissions

library(rtweet)

# --- Credentials ---
# Recommended: store these in your .Renviron file instead of hardcoding here.
# Run usethis::edit_r_environ() and add:
#
#   TWITTER_APP=your_app_name
#   TWITTER_API_KEY=xxxxxxxxxxxxxxxxxxxx
#   TWITTER_API_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
#   TWITTER_ACCESS_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
#   TWITTER_ACCESS_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
#
# Then restart R and the values will be available via Sys.getenv().

auth <- rtweet_user(
  app    = Sys.getenv("TWITTER_APP"),
  key    = Sys.getenv("TWITTER_API_KEY"),
  secret = Sys.getenv("TWITTER_API_SECRET"),
  access_token  = Sys.getenv("TWITTER_ACCESS_TOKEN"),
  access_secret = Sys.getenv("TWITTER_ACCESS_SECRET")
)

auth_as(auth)

# --- Post a tweet ---
text <- "Hello from R!"   # <-- change this to whatever you want to post

post_tweet(status = text)

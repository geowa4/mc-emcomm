defmodule McEmcomm.SightingsCrawlerTest do
  use ExUnit.Case, async: true

  alias McEmcomm.Sightings

  test "recognizes the common crawlers and preview fetchers" do
    for user_agent <- [
          "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
          "Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)",
          "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)",
          "Twitterbot/1.0",
          "Slackbot-LinkExpanding 1.0 (+https://api.slack.com/robots)",
          "Mozilla/5.0 (compatible; YandexBot/3.0; +http://yandex.com/bots)"
        ] do
      assert Sightings.crawler_user_agent?(user_agent), user_agent
    end
  end

  test "leaves ordinary browsers alone" do
    for user_agent <- [
          "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 " <>
            "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
          "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) " <>
            "Chrome/124.0.0.0 Mobile Safari/537.36",
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/605.1.15 " <>
            "(KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        ] do
      refute Sightings.crawler_user_agent?(user_agent), user_agent
    end
  end
end

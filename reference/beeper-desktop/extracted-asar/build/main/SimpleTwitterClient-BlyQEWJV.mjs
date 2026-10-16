import { USER_AGENT as l } from "./constants-BL_pdRyX.mjs";
import "path";
import "os";
import "url";
(function () {
  try {
    var i =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    i.SENTRY_RELEASE = { id: "4.3.209" };
    var t = new i.Error().stack;
    t &&
      ((i._sentryDebugIds = i._sentryDebugIds || {}),
      (i._sentryDebugIds[t] = "f13c0003-4c2d-48e9-84dc-72161f8a926c"),
      (i._sentryDebugIdIdentifier =
        "sentry-dbid-f13c0003-4c2d-48e9-84dc-72161f8a926c"));
  } catch {}
})();
const _ =
    "Bearer AAAAAAAAAAAAAAAAAAAAAPYXBAAAAAAACLXUNDekMxqa8h%2F40K4moUkGsoc%3DTYfbDKbT3jJPCEVnMYqilB28NHfOPqkca3qaAxGfsyKCs0wRbw",
  u = "https://api.twitter.com/1.1/guest/activate.json";
function d(i, t) {
  for (const e of t.data.threaded_conversation_with_injections_v2.instructions)
    switch (e.type) {
      case "TimelineAddEntries": {
        for (const s of e.entries) {
          const { itemContent: r } = s.content;
          switch (r.itemType) {
            case "TimelineTweet": {
              const n = r.tweet_results.result;
              if (n.rest_id === i) {
                const a = n.core.user_results.result;
                return {
                  id: n.rest_id,
                  user: {
                    imgURL: a.legacy.profile_image_url_https,
                    name: a.legacy.name,
                    username: a.legacy.screen_name,
                    isVerified: a.is_blue_verified,
                  },
                  text: n.legacy.full_text,
                };
              }
            }
          }
        }
        break;
      }
    }
}
let o;
class c {
  static parseTweetURL(t) {
    const [, , e, s] =
      /https?:\/\/(?:[a-z]+\.)?(twitter|x)\.com\/(.+?)\/status\/(\d+)/.exec(
        t,
      ) || [];
    if (s) return { username: e, tweetID: s };
  }
  static getClient() {
    return (o || (o = new c()), o);
  }
  async getGuestToken() {
    if (!this.guestToken || this.guestTokenAge - Date.now() > 1074e4) {
      const e = await (
        await fetch(u, {
          method: "post",
          headers: { "user-agent": l || "", authorization: _ },
        })
      ).json();
      ((this.guestTokenAge = Date.now()), (this.guestToken = e.guest_token));
    }
    return this.guestToken;
  }
  async fetchTweet(t, e) {
    const s = new URL(
      "https://api.twitter.com/graphql/HQ_gjq7zDNvSiJOCSkwUEw/TweetDetail",
    );
    (s.searchParams.set(
      "variables",
      JSON.stringify({
        focalTweetId: e,
        with_rux_injections: !1,
        includePromotedContent: !0,
        withCommunity: !1,
        withQuickPromoteEligibilityTweetFields: !1,
        withBirdwatchNotes: !1,
        withSuperFollowsUserFields: !1,
        withDownvotePerspective: !1,
        withReactionsMetadata: !1,
        withReactionsPerspective: !1,
        withSuperFollowsTweetFields: !1,
        withVoice: !0,
        withV2Timeline: !0,
      }),
    ),
      s.searchParams.set(
        "features",
        JSON.stringify({
          responsive_web_twitter_blue_verified_badge_is_enabled: !0,
          verified_phone_label_enabled: !1,
          responsive_web_graphql_timeline_navigation_enabled: !0,
          view_counts_public_visibility_enabled: !0,
          view_counts_everywhere_api_enabled: !0,
          longform_notetweets_consumption_enabled: !1,
          tweetypie_unmention_optimization_enabled: !0,
          responsive_web_uc_gql_enabled: !0,
          vibe_api_enabled: !0,
          responsive_web_edit_tweet_api_enabled: !0,
          graphql_is_translatable_rweb_tweet_is_translatable_enabled: !1,
          standardized_nudges_misinfo: !0,
          tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled:
            !1,
          interactive_text_enabled: !0,
          responsive_web_text_conversations_enabled: !1,
          responsive_web_enhance_cards_enabled: !1,
        }),
      ));
    const n = await (
      await fetch(s, {
        headers: {
          accept: "*/*",
          "accept-language": "en-US,en;q=0.9",
          "user-agent": l || "",
          authorization: _,
          "content-type": "application/json",
          "sec-ch-ua": '"Not.A/Brand";v="8", "Chromium";v="114"',
          "x-guest-token": await this.getGuestToken(),
          "x-twitter-active-user": "yes",
          "x-twitter-client-language": "en",
          Referer: `https://x.com/${t}/status/${e}`,
          "Referrer-Policy": "strict-origin-when-cross-origin",
        },
        body: null,
        method: "GET",
      })
    ).json();
    return d(e, n);
  }
}
export { c as default };
//# sourceMappingURL=SimpleTwitterClient-BlyQEWJV.mjs.map

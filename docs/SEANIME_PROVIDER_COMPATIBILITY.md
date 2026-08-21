# Seanime marketplace/provider compatibility

TetoTV accepts Seanime online-stream providers without assuming one repository
layout or hard-coding provider IDs. Catalog compatibility is intentionally
separate from provider health: a catalog can parse successfully while a
provider's upstream website is unavailable or its scraper needs an update.

## Catalogs checked on 2026-08-20

- [Bas1874/Seanime-Marketplace](https://raw.githubusercontent.com/Bas1874/Seanime-Marketplace/refs/heads/main/Marketplace/Main.json), commit `997c76897394a6b6f8e6a0b9a26264bf424db0d3`: 249 entries, 63 online-stream providers.
- [ASleepyDrink/Seanime-Stuff](https://raw.githubusercontent.com/ASleepyDrink/Seanime-Stuff/refs/heads/main/marketplace.json), commit `ee27de939c8c03ba813935d73d5518569a76c693`: 132 entries, 21 online-stream providers.
- [Pal-droid/Seanime-Providers](https://raw.githubusercontent.com/Pal-droid/Seanime-Providers/main/marketplace/main.json), commit `28e2b77a42dafa622bbf1dc73afd7ec71c1bfb69`: 47 entries, 17 online-stream providers.
- [Carloss616/seanime-extensions](https://raw.githubusercontent.com/Carloss616/seanime-extensions/main/marketplace.json), commit `aad542c6989202870ab7eb9110e0884aa4decf15`: six plugin/custom-source entries and no online-stream providers. An empty TetoTV streaming catalog is therefore expected for this repository.

Regression fixtures are excerpts of those catalog shapes, not live-network
tests. Live repositories can change independently of an app release.

## Supported compatibility surface

- Canonical arrays, bounded named wrappers, and bounded ID-keyed catalogs.
- Relative resource URLs and common manifest/payload/type/language aliases.
- Casing-only ID drift between a catalog and its manifest.
- Manifest wrappers and catalog-only executable fields when the manifest omits
  optional summary metadata.
- Advisory working/broken/deprecated metadata. When multiple repositories
  contain the same ID, a maintained candidate wins over an explicitly broken
  one; an installed provider always remains owned by its original repository.
- Current Seanime `SearchOptions`/`Media`, legacy string search, bounded result
  wrappers, several common result/episode/source aliases, and up to four ranked
  title candidates before returning `NO_MATCH`.
- An original, bounded interoperability implementation of Seanime's public
  [`$scannerUtils` contract](https://github.com/5rahim/seanime/blob/main/internal/extension_repo/goja_plugin_types/core.d.ts),
  invocation-local bounded `$store`/`$storage`, and the existing DOM, request,
  Buffer, CryptoJS, URL, sleep, and HLS bridges. TetoTV's scanner adapter was
  implemented independently from the documented API shape and observable
  behavior; it does not embed or derive from Seanime implementation source.

## Trust and resource limits

Compatibility adapters do not relax executable trust or network safety.
Catalogs, manifests, payloads, wrapper depth, entry counts, JavaScript heap and
runtime, request count/concurrency/response bytes, redirects, and returned
streams remain bounded. Repository, manifest, payload, request, subtitle, and
stream targets must use public HTTPS; DNS is validated and socket connections
are pinned to the validated public address. A repository with the same provider
ID cannot silently replace code installed from a different repository.

Provider diagnostics record only bounded IDs, versions, hosts, stages, and
reason enums. Full URLs, search queries, response bodies, cookies, credentials,
and raw third-party exception text are excluded.

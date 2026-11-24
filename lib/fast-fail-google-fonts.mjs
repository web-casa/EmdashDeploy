// Non-invasive Node.js build-time preload hook (--import).
// When EMDASH_FAST_FAIL_GOOGLE_FONTS=1 and no HTTP(S)/ALL proxy is configured,
// fast-fails requests to fonts.google.com / fonts.gstatic.com so Astro's unifont
// immediately falls back cleanly instead of blocking 90-120s on unreachable
// Google endpoints in mainland China / air-gapped networks.

const enabled = process.env.EMDASH_FAST_FAIL_GOOGLE_FONTS === "1";
const hasProxy = Boolean(
	process.env.HTTPS_PROXY ||
	process.env.https_proxy ||
	process.env.ALL_PROXY ||
	process.env.all_proxy
);

if (enabled && !hasProxy && typeof globalThis.fetch === "function") {
	globalThis.__emdashFastFailGoogleFontsInstalled = true;
	const origFetch = globalThis.fetch.bind(globalThis);
	const blockedHosts = new Set(["fonts.google.com", "fonts.gstatic.com"]);

	globalThis.fetch = async function patchedFetch(input, init) {
		try {
			const rawUrl =
				typeof input === "string"
					? input
					: input instanceof URL
						? input.href
						: typeof input?.url === "string"
							? input.url
							: "";
			if (rawUrl) {
				const parsed = new URL(rawUrl);
				if (blockedHosts.has(parsed.hostname.toLowerCase())) {
					const err = new Error(
						`Fast-failed unreachable font host ${parsed.hostname} (EMDASH_FAST_FAIL_GOOGLE_FONTS=1)`
					);
					err.name = "AbortError";
					throw err;
				}
			}
		} catch (e) {
			if (e?.name === "AbortError") {
				throw e;
			}
		}
		return origFetch(input, init);
	};
}

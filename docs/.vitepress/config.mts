import { defineConfig } from "vitepress";

export default defineConfig({
	base: process.env.DOCS_BASE ?? "/",
	title: "Pulse",
	description: "Externally evaluable absolute-time sequences for Roblox.",
	cleanUrls: true,
	themeConfig: {
		nav: [
			{ text: "Pulse", link: "/" },
			{ text: "Guides", link: "/guides/getting-started" },
			{ text: "API", link: "/api/" },
			{ text: "Architecture", link: "/architecture" },
		],
		sidebar: [
			{
				text: "Pulse",
				collapsed: true,
				items: [
					{ text: "Overview", link: "/" },
					{ text: "Architecture", link: "/architecture" },
				],
			},
			{
				text: "Guides",
				collapsed: true,
				items: [
					{ text: "Getting started", link: "/guides/getting-started" },
					{ text: "Tempo integration", link: "/guides/tempo-integration" },
					{ text: "Verification", link: "/guides/verification" },
				],
			},
			{
				text: "API",
				collapsed: false,
				items: [
					{ text: "Package root", link: "/api/" },
					{
						text: "components/",
						collapsed: true,
						items: [
							{ text: "builder", link: "/api/components/builder" },
							{ text: "playback", link: "/api/components/playback" },
							{ text: "sequence", link: "/api/components/sequence" },
						],
					},
					{
						text: "managers/",
						collapsed: true,
						items: [
							{ text: "clockDriver", link: "/api/managers/clockDriver" },
						],
					},
					{
						text: "types/",
						collapsed: true,
						items: [
							{ text: "type index", link: "/api/types/" },
							{ text: "shared definitions", link: "/api/types/definitions" },
						],
					},
				],
			},
		],
		search: { provider: "local" },
		outline: { level: [2, 3] },
		editLink: {
			pattern: "https://github.com/emdomanus/pulse/edit/master/docs/:path",
			text: "Edit this page on GitHub",
		},
		socialLinks: [{ icon: "github", link: "https://github.com/emdomanus/pulse" }],
	},
});

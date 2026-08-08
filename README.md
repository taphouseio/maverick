# Maverick

Welcome to Maverick, a blog engine built to work with [textbundles](http://textbundle.org). It's kind of a cross between static sites (in that files are stored on and read from disk), and dynamic sites that have more complicated server logic and need some database running to contain everything.

## Why Textbundle?

Typically you'll have your pages landing on your disk separate from the posts that contain them. I wanted to build a system where posts could be truly portable, and allowed maximum flexibility when adding new content to the site. Textbundles are themselves a folder structure that contain an `assets` folder for images, linked to by the enclosed markdown file inside the bundle. It's really nice.

## How Does it Work?

Maverick is built on top of the [Vapor](https://vapor.codes) framework. Inside of the `Public` folder are subfolders called `_pages` and `_posts`. The pages folder is for static pages (such as https://example.com/about), and the posts folder is for blog posts (such as https://example.com/2018/05/28/introducing-maverick/).

The presentation is done via the [Leaf](https://docs.vapor.codes/3.0/leaf/basics/) templating syntax. There are 2 templates: `index.leaf` and `post.leaf`. The site can be customized by changing those templates, and the `styles`, `scripts`, and `fonts` folders inside of `Public`.

## Support Content

Maverick also provides a reusable `MaverickContent` library for Git-backed support documentation. Support content is stored as nested textbundles and does not require dates or date-based filenames:

```text
Resources/Support/arborist/
  index.textbundle/
    info.json
    text.md
  getting-started/
    index.textbundle/
    install.textbundle/
```

Each bundle contains `info.json` and `text.md`. Images and downloadable files may be placed in a bundle-local `assets` directory. The support metadata is stored under `io_taphouse_maverick_support` in `info.json`:

```json
{
  "version": 2,
  "type": "net.daringfireball.markdown",
  "transient": false,
  "io_taphouse_maverick_support": {
    "title": "Install Arborist",
    "description": "Install and launch Arborist.",
    "updatedAt": "2026-08-07T12:00:00Z",
    "order": 10,
    "navTitle": "Install",
    "draft": false,
    "tags": ["getting-started"]
  }
}
```

Support routes, navigation, breadcrumbs, previous/next links, Markdown rendering, and asset validation are provided by Maverick. The consuming Vapor application supplies the Leaf templates, site shell, CSS, and final view context. For example:

```swift
let configuration = try SupportContentConfiguration(
    contentRoot: URL(fileURLWithPath: "Resources/Support/arborist"),
    routePath: ["arborist", "help"],
    indexTemplate: "support-index",
    sectionTemplate: "support-section",
    articleTemplate: "support-article"
)

try app.register(collection: SupportRouteCollection(configuration: configuration) { support in
    MySiteViewContext(support: support)
})
```

The root `index.textbundle` maps to the configured route (`/arborist/help` above). A nested `index.textbundle` defines a section, while other bundles define articles. Draft articles are excluded unless `includeDrafts` is enabled.

Support content is cached as a validated snapshot. The store detects changes to the content tree and reloads it on demand, so a running site can observe new or edited articles without a rebuild or restart. If an update is invalid, the previous valid snapshot remains active. Asset links beginning with `assets/` or `./assets/` are served only from the corresponding bundle’s `assets` directory; traversal and symlink escapes are rejected.

Future plans include full API support for [micropub](https://micropub.net) and [XML-RPC](http://xmlrpc.scripting.com). I want Maverick to work exceptionally well with microblogs, and it will support title-less posts. I hope to also make things like publishing from clients such as the [Micro.blog](https://micro.blog) app or [Ulysses](https://ulyssesapp.com) work seamlessly.

Feeds will be generated with full text and truncated variants, in both [RSS](https://en.wikipedia.org/wiki/RSS) and [JSONFeed](https://jsonfeed.org). These can be used to send your content anywhere you want on the web.

## Should I Use It?

Probably not yet. It's at a very early stage of development, and built to scratch my own itch and migrate from my current Ghost blog. But if it's up your alley feel free to check it out.

## The Roadmap

There's a taskpaper file of all the things that need to get done. [Check it out here.](https://github.com/jsorge/maverick/blob/master/Maverick%20To-Do.taskpaper)

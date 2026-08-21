# Maverick

Welcome to Maverick, a blog engine built to work with [textbundles](http://textbundle.org). It's kind of a cross between static sites (in that files are stored on and read from disk), and dynamic sites that have more complicated server logic and need some database running to contain everything.

## Why Textbundle?

Typically you'll have your pages landing on your disk separate from the posts that contain them. I wanted to build a system where posts could be truly portable, and allowed maximum flexibility when adding new content to the site. Textbundles are themselves a folder structure that contain an `assets` folder for images, linked to by the enclosed markdown file inside the bundle. It's really nice.

## How Does it Work?

Maverick is built on top of the [Vapor](https://vapor.codes) framework. Inside of the `Public` folder are subfolders called `_pages` and `_posts`. The pages folder is for static pages (such as https://example.com/about), and the posts folder is for blog posts (such as https://example.com/2018/05/28/introducing-maverick/).

The presentation is done via the [Leaf](https://docs.vapor.codes/3.0/leaf/basics/) templating syntax. There are 2 templates: `index.leaf` and `post.leaf`. The site can be customized by changing those templates, and the `styles`, `scripts`, and `fonts` folders inside of `Public`.

## Bundle-backed Content

The content library can mount any textbundle tree as a path-addressable collection: documentation, a wiki, product notes, legal pages, or another site-defined content type. It can also mount one specific textbundle at one route. Bundle content uses the `io_taphouse_maverick_content` metadata namespace:

```text
Resources/Pages/
  privacy.textbundle/
    info.json
    text.md
  terms.textbundle/
    info.json
    text.md
```

Register a `BundleContentRouteCollection` and provide the consuming site’s Leaf template and view context:

```swift
let configuration = try BundleContentConfiguration(
    contentRoot: URL(fileURLWithPath: "Resources/Pages"),
    routePath: ["wiki"],
    pageTemplate: "wiki-page"
)

try app.register(collection: BundleContentRouteCollection(configuration: configuration) { page in
    MySiteViewContext(bundleContent: page)
})
```

For a single bundle, use `BundleContentConfiguration(bundleURL:routePath:pageTemplate:)`. Maverick provides the typed content context, Markdown HTML, live reload, bundle-local asset handling, and rewriting of links to other bundles in the same collection. Relative Markdown links are resolved against the current bundle, while links to external URLs are left unchanged.

Navigation items expose the bundle's complete typed metadata at `item.metadata`. Applications can add site-specific metadata without changing Maverick by placing arbitrary JSON values in the namespaced `extensions` object:

```json
{
  "io_taphouse_maverick_content": {
    "title": "Repository Commands",
    "description": "Create and run shell commands for each repository.",
    "order": 30,
    "extensions": {
      "supportType": "guide",
      "featured": true,
      "audiences": ["customers", "developers"]
    }
  }
}
```

Leaf templates can read the standard description with `#(item.metadata.description)` and application-specific values with expressions such as `#(item.metadata.extensions.supportType)`. Extension keys intended for Leaf access should use identifier-friendly names such as `supportType` rather than names containing hyphens.

The consuming application remains responsible for the Leaf template, site shell, styling, navigation presentation, and metadata markup. `MaverickMarkdownTag` is also available for templates that need to render Markdown supplied directly by the application. Support/help navigation is an optional site-level layer built on top of the same bundle model.

Future plans include full API support for [micropub](https://micropub.net) and [XML-RPC](http://xmlrpc.scripting.com). I want Maverick to work exceptionally well with microblogs, and it will support title-less posts. I hope to also make things like publishing from clients such as the [Micro.blog](https://micro.blog) app or [Ulysses](https://ulyssesapp.com) work seamlessly.

Feeds will be generated with full text and truncated variants, in both [RSS](https://en.wikipedia.org/wiki/RSS) and [JSONFeed](https://jsonfeed.org). These can be used to send your content anywhere you want on the web.

## Should I Use It?

Probably not yet. It's at a very early stage of development, and built to scratch my own itch and migrate from my current Ghost blog. But if it's up your alley feel free to check it out.

## The Roadmap

There's a taskpaper file of all the things that need to get done. [Check it out here.](https://github.com/jsorge/maverick/blob/master/Maverick%20To-Do.taskpaper)

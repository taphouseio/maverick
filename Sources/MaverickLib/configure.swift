import Leaf
import LeafKit
import Logging
import MaverickModels
import Vapor

/// Called before your application initializes.
public func configure(_ app: Application) throws {
    // Register routes to the router
    try registerRoutes(app)

    // Configure the rest of your application here
    app.leaf.configuration = MaverickLeafProvider.config
    app.views.use(.leaf)

    let siteConfig = try SiteConfigController.fetchSite()
    if siteConfig.disablePageCaching {
        app.leaf.cache.isEnabled = false
    } else {
        app.leaf.cache.isEnabled = true
    }
    
    let files: FileMiddleware
    let workingDir = DirectoryConfiguration.detect().workingDirectory
    if isDebug() {
        files = FileMiddleware(publicDirectory: "\(workingDir)/_dev/Public")
    }
    else {
        files = FileMiddleware(publicDirectory: "\(workingDir)/Public")
    }
    app.middleware.use(files)

    SiteContentChangeResponderManager.shared.registerResponder(SitePinger())

    try PathHelper.prepTheTemporaryPaths()
    MaverickLogger.shared = app.logger
    runRepeatedTask(app)
}

private enum MaverickLeafProvider {
    static var config: LeafConfiguration {
        let workingDir = DirectoryConfiguration.detect().workingDirectory
        let viewsDir: String
        if isDebug() {
            viewsDir = workingDir + "_dev/Resources/Views"
        }
        else {
            viewsDir = workingDir + "Resources/Views"
        }

        let configuration = LeafConfiguration(
            rootDirectory: viewsDir
        )

        return configuration
    }
}

private func runRepeatedTask(_ app: Application) {
    _ = app.eventLoopGroup.next().scheduleTask(in: .seconds(10)) {
        do {
            try FeedOutput.makeAllTheFeeds()
            print("Feeds have been made")
        }
        catch {
            MaverickLogger.shared?.error("Something went wrong making the feeds: \(error)")
        }

        do {
            try StaticPageRouter.updateStaticRoutes()
            print("Static routes have been updated")
        }
        catch {
            MaverickLogger.shared?.error("Something went wrong updating static routes: \(error)")
        }

        do {
            try FileProcessor.attemptToLinkImagesToPosts(imagePaths: PathHelper.incomingMediaPath.children())
            print("Images have been linked to posts from the incoming media path")
        }
        catch {
            MaverickLogger.shared?.error("Something went wrong linking images to posts: \(error)")
        }

        runRepeatedTask(app)
    }
}


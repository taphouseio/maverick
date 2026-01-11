import Leaf
import LeafKit
import Logging
import MaverickModels
import Vapor
import NIOCore

/// Called before your application initializes.
public func configure(_ app: Application) async throws {
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
    app.lifecycle.use(MaintenanceLifecycle())
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

final class MaintenanceLifecycle: LifecycleHandler {
    private struct MaintenanceTaskKey: StorageKey { typealias Value = RepeatedTask }

    private enum MaintenanceError: Error { case stepFailed }

    func didBoot(_ app: Application) throws {
        let loop = app.eventLoopGroup.next()
        let logger = app.logger

        let task = loop.scheduleRepeatedAsyncTask(
            initialDelay: .seconds(10),
            delay: .seconds(10)
        ) { _ in
            app.threadPool.runIfActive(eventLoop: loop) {
                var encounteredError = false

                do {
                    try FeedOutput.makeAllTheFeeds()
                    logger.info("Feeds have been made")
                } catch {
                    encounteredError = true
                    MaverickLogger.shared?.error("Something went wrong making the feeds: \(error)")
                }

                do {
                    try StaticPageRouter.updateStaticRoutes()
                    logger.info("Static routes have been updated")
                } catch {
                    encounteredError = true
                    MaverickLogger.shared?.error("Something went wrong updating static routes: \(error)")
                }

                do {
                    try FileProcessor.attemptToLinkImagesToPosts(imagePaths: PathHelper.incomingMediaPath.children())
                    logger.info("Images have been linked to posts from the incoming media path")
                } catch {
                    encounteredError = true
                    MaverickLogger.shared?.error("Something went wrong linking images to posts: \(error)")
                }

                if encounteredError {
                    throw MaintenanceError.stepFailed
                }
            }.map {
                logger.debug("Maintenance cycle completed")
            }
        }
        app.storage[MaintenanceTaskKey.self] = task
    }

    func shutdown(_ app: Application) {
        if let task = app.storage[MaintenanceTaskKey.self] {
            task.cancel()
            app.storage[MaintenanceTaskKey.self] = nil
        }
    }
}


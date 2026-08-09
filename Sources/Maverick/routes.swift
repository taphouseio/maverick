import Leaf
import MaverickLib
import MaverickModels
import Micropub
import Vapor

/// Register your application's routes here.
///
/// [Learn More →](https://docs.vapor.codes/3.0/getting-started/structure/#routesswift)
func registerRoutes(_ app: Application) throws {
    let config = try SiteConfigController.fetchSite()
    try app.register(collection: MicropubRouteHandler(config: MicropubHelper.makeConfig(fromSite: config)))
    try app.register(collection: StaticPageRouter(siteConfig: config))
    try app.register(collection: PostListRouteCollection(config: config))
    try app.register(collection: SinglePostRouteCollection(config: config))
    try app.register(collection: TagRouteCollection())
    try app.register(collection: AdminRouteCollection())
}

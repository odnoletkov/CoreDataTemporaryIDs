import UIKit

@main
class AppDelegate: NSObject, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground

        window = UIWindow(frame: UIScreen.main.bounds)
        window!.rootViewController = UINavigationController(rootViewController: Controller())
        window!.makeKeyAndVisible()
        return true
    }
}

import CoreData
import OSLog

class Controller: UITableViewController {

    let entity: NSEntityDescription = {
        let entity = NSEntityDescription()
        entity.name = "Entity"
        return entity
    }()

    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(
            name: "Container",
            managedObjectModel: {
                let model = NSManagedObjectModel()
                model.entities = [entity]
                return model
            }()
        )
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("\(error)")
            }
        }
        return container
    }()

    lazy var fetchedResultsController = NSFetchedResultsController(
        fetchRequest: {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity.name!)
            request.sortDescriptors = [.init(keyPath: \NSManagedObject.objectID, ascending: true)]
            return request
        }(),
        managedObjectContext: persistentContainer.viewContext,
        sectionNameKeyPath: nil,
        cacheName: nil
    )

    lazy var dataSource = UITableViewDiffableDataSource<String, NSManagedObjectID>(tableView: tableView) { [persistentContainer, fetchedResultsController] tableView, indexPath, objectID in
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let object = try! fetchedResultsController.managedObjectContext.existingObject(with: objectID)
        cell.contentConfiguration = {
            var configuration = UIListContentConfiguration.cell()
            configuration.text = object.objectID.description
            return configuration
        }()
        return cell
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        _ = dataSource
        fetchedResultsController.delegate = self
        try! fetchedResultsController.performFetch()

        let obtainPermanentIDsSwitch = UISwitch()
        obtainPermanentIDsSwitch.isOn = false

        navigationItem.titleView = {
            let label = UILabel()
            label.text = "Obtain Permanent IDs"
            let stackView = UIStackView(arrangedSubviews: [label, obtainPermanentIDsSwitch])
            stackView.spacing = 8
            return stackView
        }()

        navigationItem.rightBarButtonItem = .init(systemItem: .add, primaryAction: .init { [persistentContainer, entity] _ in
            let context = persistentContainer.viewContext
            let newObject = NSManagedObject(entity: entity, insertInto: context)
            if obtainPermanentIDsSwitch.isOn {
                try! context.obtainPermanentIDs(for: [newObject])
            }
            try! context.save()
        })
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let objectID = dataSource.itemIdentifier(for: indexPath)!
        return .init(actions: [
            .init(style: .destructive, title: "Delete") { [unowned self] _, _, _ in
                let context = persistentContainer.viewContext
                context.delete(context.object(with: objectID))
                do {
                    try context.save()
                } catch {
                    Logger().error("\(error)")
                    let alert = UIAlertController(title: "Error", message: String(describing: error), preferredStyle: .alert)
                    alert.addAction(.init(title: "OK", style: .default))
                    present(alert, animated: true)
                }
            }
        ])
    }
}

extension Controller: NSFetchedResultsControllerDelegate {
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        let diffableDataSource = tableView.dataSource as! UITableViewDiffableDataSource<String, NSManagedObjectID>
        let snapshot = snapshot as NSDiffableDataSourceSnapshot<String, NSManagedObjectID>
        let temporaryIDs = snapshot.itemIdentifiers.filter(\.isTemporaryID)
        let temporaryObjects = Dictionary(
            uniqueKeysWithValues: zip(
                temporaryIDs,
                temporaryIDs.map(controller.managedObjectContext.object(with:))
            )
        )
        try! controller.managedObjectContext.obtainPermanentIDs(for: .init(temporaryObjects.values))
        let newSnapshot = snapshot.map { objectID in
            temporaryObjects[objectID]?.objectID ?? objectID
        }
        diffableDataSource.apply(newSnapshot, animatingDifferences: true)
    }
}

extension NSDiffableDataSourceSnapshot {
    func map<T>(_ transform: (ItemIdentifierType) throws -> T) rethrows -> NSDiffableDataSourceSnapshot<SectionIdentifierType, T> where T: Hashable, T: Sendable {
        var snapshot = NSDiffableDataSourceSnapshot<SectionIdentifierType, T>()
        for section in sectionIdentifiers {
            snapshot.appendSections([section])
            snapshot.appendItems(try itemIdentifiers(inSection: section).map(transform))
        }
        return snapshot
    }
}


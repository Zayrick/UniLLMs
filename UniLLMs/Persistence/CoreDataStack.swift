//
//  CoreDataStack.swift
//  UniLLMs
//
//  Encapsulates the Core Data stack and save entry point so business layers do not manage NSPersistentContainer directly.
//  Created by Zayrick on 2026/5/11.
//

import CoreData

final class CoreDataStack {
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "UniLLMs")
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        return container
    }()

    func saveContext() {
        let context = persistentContainer.viewContext
        guard context.hasChanges else {
            return
        }

        do {
            try context.save()
        } catch {
            let nserror = error as NSError
            fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
        }
    }
}

Encrypted CoreData SQLite Store
===================

CoreData encrypted SQLite store using SQLCipher

# Project Setup

Add this repository as a submodule to your project.

    git submodule add https://github.com/calebmdavenport/encrypted-core-data.git vendor/encrypted-core-data
    git submodule update --init --recursive

## Configure OpenSSL Source for Xcode

- Download the OpenSSL source code from <http://www.openssl.org/source/>. This has been tested against `1.0.1c`.
- Untar the source and place in a known location.
- Add a new source tree in Xcode > Preferences > Locations > Source Trees called `OPENSSL_SRC` pointing to the OpenSSL source folder.

## Build the OpenSSL and SQLCipher Libraries

Add the Xcode projects found in `vendor/encrypted-core-data/vendor/sqlcipher` and `vendor/encrypted-core-data/vendor/openssl` as subprojects to your Xcode project.

Add the source files found in `vendor/encrypted-core-data/Incremental Store` to your Xcode project. Pick the appropriate targets and uncheck "copy files".

Add the `crypto` and `sqlcipher` libraries as dependencies and linked libraries to all appropriate targets.

Add the flag `-DSQLITE_HAS_CODEC` to all configurations of all appropriate targets

# Using CMDEncryptedSQLiteStore

`CMDEncryptedSQLiteStore` is a subclass of `NSIncrementalStore` that enables communication between CoreData and an SQLCipher encrypted database. It registers itself at runtime so you do not have to call `registerStoreClass:forStoreType:` on `NSPersistentStoreCoordinator`.

Using it is easy. Just set the appropriate type and a database key when you load your persistent store:

    NSDictionary *options = @{ CMDEncryptedSQLiteStorePassphraseKey : @"DB_KEY_HERE" };
    NSPersistentStore *store = [coordinator
                                addPersistentStoreWithType:CMDEncryptedSQLiteStoreType
                                configuration:nil
                                URL:databaseURL
                                options:options
                                error:&error];

# Debugging

`CMDEncryptedSQLiteStore` responds to the standard CoreData SQL debug flag. Add `-com.apple.CoreData.SQLDebug 1` as an argument to the "run" phase of your scheme to see all generated statements logged to the console.

# Improvements

This project has several areas that could be improved.

- **More Test Cases** I built several test cases that helped find bugs and improve support for things like relationships. These cases currently do not touch every feature supported by the store.
- **Migrations** The store currently supports a very small subset of lightweight migrations with inferred migration maps. I would like to imp lement more migration map parsing.
- **Persistent Store Options** You have the option to pass a number of options when adding a new store a coordinator. I added my own option which provides the database key but would like to support system options as well. Things like data protection class, SQLite pragmas, and migration options would be nice to have.
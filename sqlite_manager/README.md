# free pascal sqlitemanager
================================Synopsis================================

    A wrapper around the SQLite connection.
    Provides:
        - manual access to the database via parametrised queries and result rows like usual Lazarus' components
        - auto-convertation engine via user's versionised sql-scripts
        - storing binary data in separate multi-part files
        - optional values via tOptional type
        - logging of the convertation process and the whole sql queries
    
===============================Description===============================

    coming soon
    
==================================Usage=================================

    Download the fp_toolbox repo https://github.com/kote-kagbe/fp_toolbox
    Install component with menu Package->Open package file->sqlite_manager_package.lpk. (Compile, Use->Install, rebuild Lazarus)
    Drop the tSQLiteManager component on the form or data unit.
    Assign component's options.
    Write version 0 convertation script.
    Download sqlite3.dll from https://www.sqlite.org/download.html to your program's directory or install sqlite from your repo.
    Open the database.
    
=================================Details=================================

    coming soon
    
========================Precautions and licensing=========================

    I haven't yet tested it well so use it on your own risk.
    Any proposals and bugfixes are welcome.
    
    You are free to use it in any project with any license.
    You are free to alter and distibute the optional.pas only without taking fees for it and preserving the authorship.
    The author doesn't respond for any negative consequences probable.

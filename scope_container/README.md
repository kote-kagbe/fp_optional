# free pascal scope_container
================================Synopsis================================

    Container for tObject descendants with auto destruction option
    
===============================Description===============================

    The objects in Free Pascal are stored in the heap so programmer must free the it's memory manually with destructor.
    When multiple objects in one scope (i.e. function) are created at different time proper memory management gets complicated.
    Especially when there're any inner scopes like try-except blocks or loops or conditional statements.
    So auto memory mangement semms to be quite useful thing that Free Pascal lacks in general.
    The tScopeContainer is here to sovle the problem.
    It owns the user's object and frees is on scope end.
    
==================================Usage=================================

    Add scope_container.pas to your project path.
    Add "scope_container" to "uses" clause.
    Declare desired container type and assign your object to it.
    Use container's "get" method to gain access to your object.

    var
        my_container = specialize<tMyType>;
    begin
        if ... then
            my_container := tMyType.Create;
        ...
        if my_container then
            my_container.get.some_method;
        ...
    end.

    If you find the "get" method annoying you can store your object both in container and in variable.

    var
        my_container: specialize<tMyType>;
        my_var: tMyType;
    begin
        if ... then
            my_var := tMyType.Create;
        my_container := my_var;
        ...
        if my_container { i.e. my_var <> nil } then
            my_var.some_method;
        ...
    end.

    !!!==> Do NOT call the destructor of your object! <==!!!
    If you want to release your object call the "reset" method of scope_container.
    
=================================Details=================================

    Internally tScopeContainer is a generic record. So it is allocated when the scope starts and deallocated when the scope ends.
    Handling it's destructor gives the opportunity to manually mange it's internals.
    The tScopeContainer implements this idea.

========================Precautions and licensing=========================

    I haven't yet tested it well so use it on your own risk.
    Any proposals and bugfixes are welcome.
    
    You are free to use it in any project with any license.
    You are free to alter and distibute the optional.pas only without taking fees for it and preserving the authorship.
    The author doesn't respond for any negative consequences probable.

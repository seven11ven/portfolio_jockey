# General Prompt for how I want the application to look like

## The Idea
This application will be a project tracker. Projects will be folders created under a designated installation space that the User can configure in the app's settings.

The application will be FULLY localized. No cloud based storage, nor login or authentication. It should be designed for Linux and Android devices.


## The Features
* Creating a project
    - Users will be able to create Projects from the homepage.
    - Users will also be able to name the project and give it cover art.
    - Users will be able to create tags within Projects to help organize files uploaded to the Project
    - Projects will have descriptions Users can assign to them.
    - Projects will have "..."(three dots in a corner) next to their name that give the User  the following options when clicked(or pressed):
        - Rename the Project
        - Export the Project as a:
            - Zip File
            - Tar File
        - Delete the project(confirmation screen needed)
* Uploading a file
    - When 'uploading' files, Users should be prompted a confirmation screen to confirm or cancel the action.
    - Files should be ENCRYPTED upon being uploaded to the Project
    - Files, when right-clicked on a computer/laptop(or long pressed on a mobile device), should give the User the following options:
        - Delete File from Device(Deleting the Original)
        - Delete File from Project(Deleting the File that's in the Project)
        - Delete File from Both(Delete both the Original File and the File that's in the Project)
        * All three options MUST have confirmation screens to allow the User to confirm or deny the action
* Change App Settings(Usually a cog icon in a corner of the application window)
    - ALlow the User to change the Application Color Scheme
    - Allow the User to view the Application Version
    - Allow the User to change the location of where Project Folders are made
    - Allow the User to bulk export the Projects as the following file formats:
        - Zip File
        - Tar File

## Requirements
* Any feature in the app that modifies any files should greet the User with a confirmation screen allowing them to Confirm or Cancel said action.
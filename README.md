# Gmail Parser

Parses emails of a specific label in gmail to check for uploaded documents and save attachments to server.

## Getting Started

These instructions will get you a copy of the project up and running on your local machine for development and testing purposes.

### Installing

Install gmail api gem:
gem install google-api-client -v 0.24.3
gem install googleauth -v 0.6.6

Configure a new project in https://console.developers.google.com/ and add Gmail API to your project.
Download OAuth2 credentials of Gmail API. Put contents of that file to root of the project in credentials.json file.

Login to Gmail and create filter settings to add contents to a specific label. Put ID of that label in config.yaml file. (To get ID, you can use list_user_labels function (definition in google-api-client-0.24.3/generated/google/apis/gmail_v1/service.rb))

Configure DB credentials in config.yaml file.

Configure start_date from which you want to start parsing emails in config.yaml file.

## Running the project

Run ruby emailparser.rb. Follow the instruction when running for first time.


# Gmail Parser

Parses emails of a specific label in gmail to check for uploaded documents and save attachments to server.

## Getting Started

These instructions will get you a copy of the project up and running on your local machine for development and testing purposes.

### Installing

Install dependencies:
sudo bundle install

Configure a new project in https://console.developers.google.com/ and add Gmail API to your project.
Download OAuth2 credentials of Gmail API. Put contents of that file to root of the project in credentials.json file.

Create a copy of config.yaml.sample file named config.yaml.

Login to Gmail, create a new label. This label will be used to fetch emails from.
Add that label's name to config.yaml file.
Create filter settings to add emails to that label. 

Configure DB credentials in config.yaml file.

Configure start_date from which you want to start parsing emails in config.yaml file.

## Running the project

Run ruby emailparser.rb. Follow the instruction when running for first time.


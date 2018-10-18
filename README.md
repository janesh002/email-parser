# Gmail Parser

Parses emails of a specific label in gmail to check for uploaded documents and save attachments to server.

## Getting Started

These instructions will get you a copy of the project up and running on your local machine for development and testing purposes.

### Installing

Install dependencies:
sudo bundle install

Create a new project in Google Developer's console from https://console.developers.google.com/projectcreate.
After creation, if you get "Page not viewable for organizations. To view this page, select a project.", click on Select and select your project.
In dashboard, under "Getting Started", select "Enable APIs and get credentials like keys" section.
Click on Enable API & Services and search Gmail API. Click on it and enable it.
Click on Credentials section in left menu and select "Create Credential". For "Where will you be calling the API from?", select "Other UI". For "What data will you be accessing?", select "User Data". Follow remaining on-screen steps. Download credentials. Put the contents of those file to root of the project in credentials.json file.

Open Gmail (http://www.gmail.com/).
Now, we need to create filter settings specifically for our email parser.

For reference, following steps can be used on how to create a gmail filter setting and apply a label to all filtered emails:
- Open Gmail.
- In the search box at the top, click the Down arrow Down Arrow.
- Enter your search criteria. If you want to check that your search worked correctly, see what emails show up by clicking Search. 
- At the bottom of the search window, click Create filter.
- Select Apply the label option, and choose label.
- Create a new label separately for our email parser. All filter settings we will be creating will put emails to this label only.

Using above steps, create settings as below:
- Subject has "KYC" and has attachment
- Subject has "gst" and has attachment
- Subject has "document address" and has attachment
- Subject has "bank statement" and has attachment
- Subject has "itr" and has attachment
- Subject has "document pan" and has attachment

Create a copy of config.yaml.sample file named config.yaml. Fill in following details in config.yaml file:
- Add the Gmail label's name to LABEL_NAME key.
- Add DB details (db_host, db_user, db_pass, db_name). Make sure DB name (db_name) which is configured is created in MySQL.
- Add start date(start_date) from which you want to start parsing emails.
- Add URL of email verification API (email_api_url).
- Add URL of document upload API (document_upload_url).


## Running the project

Run ruby emailparser.rb. Follow the instruction when running for first time.


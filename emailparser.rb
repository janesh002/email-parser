require 'google/apis/gmail_v1'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'fileutils'
require 'pp'
require 'date'
require 'mysql2'
require 'yaml'
require 'net/http'
require 'net/sftp'

# Loading configuration details
CONFIGURATIONS = YAML::load_file('config.yaml')

# Gmail API constants.
OOB_URI = CONFIGURATIONS['OOB_URI'].freeze
APPLICATION_NAME = CONFIGURATIONS['APPLICATION_NAME'].freeze
CREDENTIALS_PATH = CONFIGURATIONS['CREDENTIALS_PATH'].freeze
TOKEN_PATH = CONFIGURATIONS['TOKEN_PATH'].freeze
SCOPE = Google::Apis::GmailV1::AUTH_SCOPE

# Database credentials.
DB_HOST  = CONFIGURATIONS['db_host']
DB_USER  = CONFIGURATIONS['db_user']
DB_PASS  = CONFIGURATIONS['db_pass']
DB_NAME  = CONFIGURATIONS['db_name']

# User ID for which emails are parsed.
USER_ID  = CONFIGURATIONS['user_id']

# Date (yyyy/mm/dd) from which emails should be parsed.
START_DATE = DateTime.parse(CONFIGURATIONS['start_date'])

# Label under which relevant emails are nested.
LABEL_ID  = CONFIGURATIONS['label_id']

# API URL for verifying email address.
EMAIL_API_URL  = CONFIGURATIONS['email_api_url']
DOCUMENT_UPLOAD_URL  = CONFIGURATIONS['document_upload_url']

# Approx time taken (in minutes) by cron run.
# This is used along with "last email parsing time" as more emails might have come 
# when cron was being run
CRON_APPROX_RUN_TIME = CONFIGURATIONS['CRON_APPROX_RUN_TIME'].to_s

##
# Ensure valid credentials, either by restoring from the saved credentials
# files or intitiating an OAuth2 authorization. If authorization is required,
# the user's default browser will be launched to approve the request.
#
# @return [Google::Auth::UserRefreshCredentials] OAuth2 credentials
def authorize
  client_id = Google::Auth::ClientId.from_file(CREDENTIALS_PATH)
  token_store = Google::Auth::Stores::FileTokenStore.new(file: TOKEN_PATH)
  authorizer = Google::Auth::UserAuthorizer.new(client_id, SCOPE, token_store)
  user_id = 'default'
  credentials = authorizer.get_credentials(user_id)
  if credentials.nil?
    url = authorizer.get_authorization_url(base_url: OOB_URI)
    puts 'Open the following URL in the browser and enter the ' \
         "resulting code after authorization:\n" + url
    code = gets
    credentials = authorizer.get_and_store_credentials_from_code(
      user_id: user_id, code: code, base_url: OOB_URI
    )
  end
  credentials
end

##
# Sends an HTTP request to the API to verify email address.
# 
# @param [String] emailId
#   The sender's email address.
# 
# @return API response body
def verify_email_address(emailId)
  url = URI.parse(EMAIL_API_URL + '?eid=' + emailId)
  req = Net::HTTP::Get.new(url.to_s)
  res = Net::HTTP.start(url.hostname, url.port) {|http|
    http.request(req)
  }
  res.body
end

##
# Sends data to document upload API.
# 
# @param [String] loan_applicant_id
#   Applicant's load ID.
# 
# @param [String] document_category
#   Uploaded document's category.
# 
# @param [String] document_type
#   Uploaded document's type.
# 
# @param [String] image_data
#   The hexadecimal code of image.
# 
# @return API response body
def upload_document(loan_applicant_id, document_category, document_type, image_data)
  uri = URI.parse(DOCUMENT_UPLOAD_URL)
  request_data = {
   :loan_applicant_id => loan_applicant_id,
   :document_category => document_category,
   :document_type => document_type,
   :image_data => image_data,
  }
  res = Net::HTTP.post_form(uri,request_data)
  res.code
  res.body
end

# Main code starts here

# Initialize the API
service = Google::Apis::GmailV1::GmailService.new
service.client_options.application_name = APPLICATION_NAME
service.authorization = authorize

# MySQL Connection
client = Mysql2::Client.new(:host => DB_HOST, :username => DB_USER, :password => DB_PASS, :database => DB_NAME)

# Create table query for storing email history.
createTable = client.query('
  CREATE TABLE IF NOT EXISTS `email_parsing_history` (
   `id` int(11) NOT NULL AUTO_INCREMENT,
   `user_id` varchar(1000) NOT NULL,
   `message_id` varchar(1000) NOT NULL,
   `history_id` varchar(1000) NOT NULL,
   `email_subject` varchar(1000) NOT NULL,
   `sender_id` varchar(1000) NOT NULL,
   `valid_sender` int(11) NOT NULL,
   `attachment_id` varchar(1000) NOT NULL,
   `created_on` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
   PRIMARY KEY (`id`)
  ) ENGINE=InnoDB DEFAULT CHARSET=latin1;
')

##
# Read datetime when last email was parsed.
# CRON_APPROX_RUN_TIME (in minutes) is subtracted as more emails might have come when cron was being run.
lastHistoryCreatedOn = client.query('
  SELECT DATE_ADD(MAX(created_on), INTERVAL -' + CRON_APPROX_RUN_TIME + ' MINUTE) as last_created_on
  FROM email_parsing_history
')

# lastCreatedTimestamp - Timestamp after which emails are needed
lastCreatedTimestamp = ''
lastHistoryCreatedOn.each {
  |lastCreated|
  lastCreatedOn = lastCreated['last_created_on'].to_s
  if lastCreatedOn != ''
    lastCreatedOnDate = DateTime.parse(lastCreatedOn)
    if lastCreatedOnDate > START_DATE
      lastCreatedTimestamp = lastCreatedOnDate.to_time.to_i
    else
      lastCreatedTimestamp = START_DATE.to_time.to_i
    end
    lastCreatedTimestamp = lastCreatedTimestamp.to_s
  end
}

queryString = ''
if (lastCreatedTimestamp != '')
  queryString += ' after: ' + lastCreatedTimestamp
end

# Fetch user's emails
result = service.list_user_messages(USER_ID, label_ids: LABEL_ID, q: queryString)

# Check for no email found.
if result.result_size_estimate == 0
  abort('No messsages found.')
end

# historyUpdateQueryStr - Query string of insert queries for storing email parse history.
historyUpdateQueryStr = '
  INSERT INTO email_parsing_history (user_id, message_id, history_id, email_subject, sender_id, valid_sender, attachment_id)
  VALUES'
# updateHistory - Flag to check if insert query is needed to be run.
updateHistory = 0

# Looping all emails fetched
result.messages.each {
  |message|
  # messageId - Unique ID of message.
  messageId = message.id
  # Fetch message details from messageId.
  messageDetails = service.get_user_message(USER_ID, messageId)
  # historyId - History IDs increase chronologically with every change to a mailbox.
  historyId = messageDetails.history_id;
  # Read DB to check if email has been parsed earlier.
  @parsingHistory = client.query('
    SELECT 1 FROM email_parsing_history
    WHERE message_id = "' + messageId + '"
  ')
  # If email has been parsed before, we continue to next iteration
  if (@parsingHistory.count != 0)
    next
  end
  # emailPayloadHeader - Headers of the email's payload
  emailPayloadHeader = messageDetails.payload.headers
  # senderValid - Flag signifying whether sender exists in system.
  senderValid = 0
  senderEmailId = emailSubject = ''
  emailPayloadHeader.each {
    |header|
    if header.name == 'Subject'
      emailSubject = header.value
    end
    if header.name == 'From'
      if header.value =~ /\<(.*?)\>/
        senderEmailId = $1
        # Uses email verification API
        if verify_email_address(senderEmailId)
          senderValid = 1
        end
      end
    end
  }
  # attachmentId - Attachment ID received from Gmail
  # attachmentExtension - File extension of attachment. Re-used when recreating a same file.
  attachmentId = attachmentExtension = ''
  # Traversing message payload for fetching attachment details
  messageDetails.payload.parts.each {
    |payloadPart|
    if payloadPart.body.attachment_id != nil
      attachmentId = payloadPart.body.attachment_id
      attachmentExtension = File.extname(payloadPart.filename)
    end
  }

  # Details of loan applicant. These details should be received from email verification API.
  loan_applicant_id = 'xxx'
  document_category = 'xxx'
  document_type = 'xxx'

  # Attachment extracted only if sender is valid.
  if senderValid == 1
    # Gmail API returns attachment file data in hexadecimal.
    attachmentDetails = service.get_user_message_attachment(USER_ID, messageId, attachmentId)

    # Uses document upload API.
    upload_document(loan_applicant_id, document_category, document_type, attachmentDetails.data)

    ##
    # Block to write file data to a new file to recreate attachment and save in
    # "./files/" directory locally.
    #

    # fileName = 'files/' + senderEmailId + '_' + messageId + attachmentExtension
    # f = File.new(fileName, 'w')
    # f.write(attachmentDetails.data)
    # f.close
  end
  
  # Concatenate insert query to be executed later.
  historyUpdateQueryStr += '
    ("' + USER_ID + '", "' + messageId + '", "' + historyId.to_s + '", "' + emailSubject.to_s + '", "' + senderEmailId + '", ' + senderValid.to_s + ', "' + attachmentId.to_s + '"),'
  updateHistory = 1
}
# Save email parsing details to DB.
if updateHistory == 1
  # chop is used to remove comma(,) at the end
  historyUpdateQueryStr = historyUpdateQueryStr.strip.chop + ';'
  @updateParseHistory = client.query(historyUpdateQueryStr)
end
require 'google/apis/gmail_v1'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'fileutils'
require 'pp'
require 'date'
require 'mysql2'
require 'yaml'

# Loading configuration details
CONFIGURATIONS = YAML::load_file('config.yaml')

# Gmail API constants
OOB_URI = CONFIGURATIONS['OOB_URI'].freeze
APPLICATION_NAME = CONFIGURATIONS['APPLICATION_NAME'].freeze
CREDENTIALS_PATH = CONFIGURATIONS['CREDENTIALS_PATH'].freeze
TOKEN_PATH = CONFIGURATIONS['TOKEN_PATH'].freeze
SCOPE = Google::Apis::GmailV1::AUTH_SCOPE

# Database credentials
DB_HOST  = CONFIGURATIONS['db_host']
DB_USER  = CONFIGURATIONS['db_user']
DB_PASS  = CONFIGURATIONS['db_pass']
DB_NAME  = CONFIGURATIONS['db_name']

# User ID for which emails are parsed
USERID  = CONFIGURATIONS['user_id']

# Date (yyyy/mm/dd) from which emails should be parsed
STARTDATE = DateTime.parse(CONFIGURATIONS['start_date'])

# Label under which relevant emails are nested
LABELID  = CONFIGURATIONS['label_id']

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

# Initialize the API
service = Google::Apis::GmailV1::GmailService.new
service.client_options.application_name = APPLICATION_NAME
service.authorization = authorize

# MySQL Connection
client = Mysql2::Client.new(:host => DB_HOST, :username => DB_USER, :password => DB_PASS, :database => DB_NAME)

##
# Read datetime when last email was parsed.
# 5 minutes (random fig.) are subtracted as more emails might have come when cron was being run.
lastHistoryCreatedOn = client.query('
  SELECT DATE_ADD(MAX(created_on), INTERVAL -5 MINUTE) as last_created_on
  FROM email_parsing_history
')

# lastCreatedTimestamp - Timestamp after which emails are needed
lastCreatedTimestamp = ''
lastHistoryCreatedOn.each {
  |lastCreated|
  lastCreatedOn = lastCreated['last_created_on'].to_s
  if lastCreatedOn != ''
    lastCreatedOnDate = DateTime.parse(lastCreatedOn)
    if lastCreatedOnDate > STARTDATE
      lastCreatedTimestamp = lastCreatedOnDate.to_time.to_i
    else
      lastCreatedTimestamp = STARTDATE.to_time.to_i
    end
    lastCreatedTimestamp = lastCreatedTimestamp.to_s
  end
}

# Emails should have attachment
queryString = ''
if (lastCreatedTimestamp != '')
  queryString += ' after: ' + lastCreatedTimestamp
end

# Fetch user's emails
result = service.list_user_messages(USERID, label_ids: LABELID, q: queryString)

# Check for no email found.
if result.result_size_estimate == 0
  abort('No messsages found.')
end

# validUserIds will be replaced by the API call from mintifi system
validUserIds = ['janesh.khanna@ebizontek.com']

# Looping all emails fetched
result.messages.each {
  |message|
  # messageId - Unique ID of message.
  messageId = message.id
  # Fetch message details from messageId.
  messageDetails = service.get_user_message(USERID, messageId)
  # historyId - History IDs increase chronologically with every change to a mailbox.
  historyId = messageDetails.history_id;
  # Read DB to check if email has been parsed earlier.
  @parsingHistory = client.query('
    SELECT 1 FROM email_parsing_history
    WHERE message_id = "' + messageId + '" AND history_id = "' + historyId.to_s + '"
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
        if validUserIds.include?senderEmailId
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
  # Attachment extracted only if sender is valid.
  if senderValid == 1
    # Gmail API returns attachment file data in hexadecimal.
    # Write it to a new file to recreate attachment. Save it in "./files/" folder.
    attachmentDetails = service.get_user_message_attachment(USERID, messageId, attachmentId)
    fileName = 'files/' + senderEmailId + '_' + messageId + attachmentExtension
    f = File.new(fileName, 'w')
    f.write(attachmentDetails.data)
    f.close
  end
  
  # Save email parsing details to DB.
  @updateParseHistory = client.query('
    INSERT INTO email_parsing_history (user_id, message_id, history_id, email_subject, sender_id, valid_sender, attachment_id)
    VALUES ("' + USERID + '", "' + messageId + '", "' + historyId.to_s + '", "' + emailSubject.to_s + '", "' + senderEmailId + '", ' + senderValid.to_s + ', "' + attachmentId.to_s + '")
  ')
}
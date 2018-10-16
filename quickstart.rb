require 'google/apis/gmail_v1'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'fileutils'
require 'pp'
require 'date'
require 'mysql2'
require 'yaml'

OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'.freeze
APPLICATION_NAME = 'Gmail API Ruby Quickstart'.freeze
CREDENTIALS_PATH = 'credentials.json'.freeze
TOKEN_PATH = 'token.yaml'.freeze
SCOPE = Google::Apis::GmailV1::AUTH_SCOPE

# Loading configuration details
configurations = YAML::load_file('config.yaml')

@db_host  = configurations['db_host']
@db_user  = configurations['db_user']
@db_pass  = configurations['db_pass']
@db_name  = configurations['db_name']

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

user_id  = configurations['user_id']
# MySQL Connection
client = Mysql2::Client.new(:host => @db_host, :username => @db_user, :password => @db_pass, :database => @db_name)

# Read datetime when last email was parsed.
# 5 minutes (random fig.) are subtracted as more emails might have come when cron was being run.
lastHistoryCreatedOn = client.query('SELECT DATE_ADD(MAX(created_on), INTERVAL -5 MINUTE) as last_created_on FROM email_parsing_history')
lastCreatedTimestamp = ''
lastHistoryCreatedOn.each {
  |lastCreated|
  lastCreatedOn = lastCreated['last_created_on'].to_s
  if lastCreatedOn != ''
    date = DateTime.parse(lastCreatedOn)
    lastCreatedTimestamp = date.to_time.to_i
    lastCreatedTimestamp = lastCreatedTimestamp.to_s
  end
}

queryString = 'has:attachment'
if (lastCreatedTimestamp != '')
  queryString += ' after: ' + lastCreatedTimestamp
end

# Fetch user's emails
result = service.list_user_messages(user_id, q: queryString)

if result.result_size_estimate == 0
  abort('No messsages found.')
end

# testMessageIds = ['16676a0b0e4fbc71', '16676687981e049f', '166689f12fd0ca55']
validUserIds = ['janesh.khanna@ebizontek.com']
result.messages.each {
  |message|
  messageId = message.id
  # if testMessageIds.include?(messageId)
    # Fetch message details from messageId
    messageDetails = service.get_user_message(user_id, messageId)
    history_id = messageDetails.history_id;
    # See if email has been parsed earlier.
    @parsingHistory = client.query('
      SELECT 1 FROM email_parsing_history
      WHERE message_id = "' + messageId + '" AND history_id = "' + history_id.to_s + '"
    ')
    if (@parsingHistory.count != 0)
      next
    end
    emailPayloadHeader = messageDetails.payload.headers
    subjectMatched = senderValid = 0
    senderEmailId = emailSubject = attachment_id = ''
    emailPayloadHeader.each {
      |header|
      if header.name == 'Subject'
        emailSubj = header.value.downcase
        if emailSubj.include? 'kyc document - pan'
          subjectMatched = 1
        elsif emailSubj.include? 'kyc document - address'
          subjectMatched = 1
        elsif emailSubj.include? 'bank statement'
          subjectMatched = 1
        elsif emailSubj.include? 'gst details'
          subjectMatched = 1
        elsif emailSubj.include? 'itr details'
          subjectMatched = 1
        end
        if (subjectMatched)
          emailSubject = header.value
        end
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
    attachment_id = attachmentExtension = ''
    # Traversing message payload for fetching attachment details
    messageDetails.payload.parts.each {
      |payloadPart|
      if payloadPart.body.attachment_id != nil
        attachment_id = payloadPart.body.attachment_id
        attachmentExtension = File.extname(payloadPart.filename)
      end
    }
    validEmail = 0
    # Check if email is valid, extract attachment
    if subjectMatched == 1 && senderValid == 1
      # Gmail API returns file data in hexadecimal. Write it to a new file to recreate attachment
      attachmentDetails = service.get_user_message_attachment(user_id, messageId, attachment_id)
      fileName = 'files/' + senderEmailId + '_' + messageId + attachmentExtension
      f = File.new(fileName, 'w')
      f.write(attachmentDetails.data)
      f.close
      validEmail = 1
    end
    
    # Save email parsing details to DB.
    @updateParseHistory = client.query('
      INSERT INTO email_parsing_history (user_id, message_id, history_id, email_subject, sender_id, valid_subject, valid_sender, valid_email, attachment_id)
      VALUES ("' + user_id + '", "' + messageId + '", "' + history_id.to_s + '", "' + emailSubject.to_s + '", "' + senderEmailId + '", ' + subjectMatched.to_s + ', ' + senderValid.to_s + ', ' + validEmail.to_s + ', "' + attachment_id.to_s + '")
    ')
  # end
}
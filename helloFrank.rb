# => Joseph Malandruccolo
# => HW7 CSPP 51083


require 'rubygems'
require 'sinatra'
require 'aws-sdk'
require_relative 'secret'
require 'open-uri'

# => CONSTANTS
S3_URL_PREFIX = "https://s3.amazonaws.com/cloudhw1/"


# => index page
get '/' do
	#@contacts = get_contacts
	#@contact_urls = @contacts.map { |x| lambda { |y| "#{S3_URL_PREFIX}" + y}.call x.key }
	@parsed_contacts = parse_contacts get_contacts
	erb :index_page
end


# => subscriber page
get '/mailing_list' do
	@mailing_lists = get_sns_topics
	erb :mailing_list
end


# => contact input page
get '/add_contact' do
	erb :add_contact
end


# => subscribe user
post '/subscribe' do

	topic_name = params[:list]
	subscriber_endpoint = params[:endpoint]

	@success = subscribe subscriber_endpoint, topic_name
	erb :subscribed

end


# => create contact
post '/create_contact' do
	first_name = params[:first_name]
	last_name = params[:last_name]
	scrub_name first_name
	scrub_name last_name
	add_contact_to_simpledb first_name, last_name
	add_contact_to_s3 first_name, last_name
	#send notification

	redirect to("/")

end





# => retrieve raw S3 objects
def get_contacts

	s3 = AWS::S3.new(access_key_id: $access_key, secret_access_key: $secret_key)
	cloudhw1 = s3.buckets['cloudhw1']

	contacts = []
	cloudhw1.objects.each do |obj|
		contacts.push(obj)
	end

	contacts

end


# => retrieve raw SNS topics
def get_sns_topics

	sns = AWS::SNS.new(access_key_id: $access_key, secret_access_key: $secret_key)
	topics = sns.topics

	topics

end


# => subscribe an endpoint to a topic
def subscribe endpoint, toDisplayName

	sns = AWS::SNS.new(access_key_id: $access_key, secret_access_key: $secret_key)
	topics = sns.topics

	target_topic = nil
	topics.each do |t|
		if t.display_name.eql? toDisplayName
			target_topic = t
		end
	end

	if !target_topic.nil?
		target_topic.subscribe endpoint

		return true

	end

	return false

end


# => add a contact to simple db
def add_contact_to_simpledb first_name, last_name


	sdb = AWS::SimpleDB.new(access_key_id: $access_key, secret_access_key: $secret_key)
	domain = sdb.domains['malandruccolodb']
	contact = domain.items["#{first_name}#{last_name}"]
	contact.attributes['firstName'].add first_name
	contact.attributes['lastName'].add last_name

	return

end


# => add contact to s3
def add_contact_to_s3 first_name, last_name

	s3 = AWS::S3.new(access_key_id: $access_key, secret_access_key: $secret_key)
	cloudhw1 = s3.buckets['cloudhw1']

	s3_key = generate_s3_key first_name, last_name
	s3_html = generate_s3_html first_name, last_name

	cloudhw1.objects.create(s3_key, s3_html)
	
	return

end


# => read the saw S3 html and extract the needed data
def parse_contacts contacts

	names = []
	contacts.each do |c|
		raw_html = c.read
		data_tags = raw_html.split("<td>")
		full_name = "#{data_tags[1]} #{data_tags[2]}"
		contact = Contact.new
		contact.name = full_name.gsub("</td>", "")
		contact.s3_link = "#{S3_URL_PREFIX}#{c.key}"
		names.push contact
	end
	
	names

end


# => generate the s3 key name
def generate_s3_key first_name, last_name

	"#{first_name}#{last_name}#{Time.new.to_i}.html".downcase
	
end


# => generate the html file to store in s3
def generate_s3_html first_name, last_name

	header = "<html><head><title>Contact Page</title></head><body><table><tr><th>First Name</th><th>Last Name</th><th></th></tr>"
	data = "<tr><td>#{first_name}</td><td>#{last_name}</td><td></td></tr></table></body></html>"
	
	"#{header}#{data}"

end


# => scrub name, per specifications
def scrub_name name
	raise "too few letters in #{name}" unless name.length >= 1
	raise "too many letters in #{name}" unless name.length <= 16
	raise "illegal characters in #{name}" unless /^[a-zA-z]/.match name

	return

end


# => object to bridge S3 output to data needed in the view
class Contact

	attr_accessor :name, :s3_link
	attr_reader :name, :s3_link

end


__END__

<!DOCTYPE HTML>
@@index_page
<html>
	<head>
		<title>Index Page</title>
	</head>
	<body>
		<h1>Contacts</h1>
		<ul>
			<li><a href='#'>home</a></li>
			<li><a href='/mailing_list'>mailing lists</a></li>
			<li><a href='/add_contact'>add a contact</a></li>
		</ul>
		<table>
			<tr>
				<th>Name</th>
				<th>Link</th>
			</tr>
		<%	@parsed_contacts.each do |c| %>
		<tr>
			<td><%=	c.name 	%></td>
			<td><%=	c.s3_link %></td>
		</tr>
		<% end %>
	</table>
	</body>
</html>


@@mailing_list
<html>
	<head>
		<title>Mailing Lists</title>
	</head>
	<body>
		<h1>Mailing lists</h1>
		<ul>
			<li><a href='/'>home</a></li>
			<li><a href='#'>mailing lists</a></li>
			<li><a href='/add_contact'>add a contact</a></li>
		</ul>
		<form name="sns_form" action="/subscribe" method="post">
		<%	@mailing_lists.each do |m|	%>
				<input type="radio" name="list" value=<%= '"' + "#{m.display_name}" + '"' %>>
					<%= "#{m.display_name}" %><br>
		<%	end 	%>
		Email address or url: <input type="text" name="endpoint"><br>
		<input type="submit" value="subscribe">
		</form>
	</body>
</html>


@@add_contact
<html>
	<head>
		<title>Add contact</title>
	</head>
	<body>
		<h1>Add a contact</h1>
		<ul>
			<li><a href='/'>home</a></li>
			<li><a href='/mailing_list'>mailing lists</a></li>
			<li><a href='#'>add a contact</a></li>
			<form name="contact_form" action="/create_contact" method="post">
				First name: <input type="text" name="first_name"><br>
				Last name: <input type="text" name="last_name">
				<input type="submit" value="create contact">
			</form>
		</ul>
	</body>
</html>


@@subscribed
<html>
	<head>
		<title>subscribed</title>
	</head>
	<body>
		<ul>
			<li><a href='/'>home</a></li>
			<li><a href='/mailing_list'>mailing lists</a></li>
			<li><a href='/add_contact'>add a contact</a></li>
		</ul>
		<% if @success %>
			successfully subscribed!
		<%	else  %>
			failed to subscribe
		<%	end  %>
	</body>
</html>
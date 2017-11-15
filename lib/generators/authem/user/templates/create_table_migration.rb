<% MIGRATION_BASE = if Rails.version >= '5.0'
                   ActiveRecord::Migration[5.0]
                 else
                   ActiveRecord::Migration
                 end
%>
class <%= migration_class_name %> < <%= MIGRATION_BASE %>
  def change
    create_table :<%= table_name %> do |t|
      t.string :email,                null: false
      t.string :password_digest,      null: false
      t.string :password_reset_token, null: false, limit: 60
<% attributes.each do |attribute| -%>
<% if attribute.password_digest? -%>
      t.string :password_digest<%= attribute.inject_options %>
<% else -%>
      t.<%= attribute.type %> :<%= attribute.name %><%= attribute.inject_options %>
<% end -%>
<% end -%>
<% if options[:timestamps] %>
      t.timestamps
<% end -%>
    end
<% attributes_with_index.each do |attribute| -%>
    add_index :<%= table_name %>, :<%= attribute.index_name %><%= attribute.inject_index_options %>
<% end -%>
  end
end

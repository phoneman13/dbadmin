ActiveAdmin.register_page "Top Refer" do

  content title: "Top 100 Clicked Links/Sources" do
    table_for UserAttributes.referer_only.pluck(:value).group_by {|r| r}.values.sort.reverse.first(100).each do
      column "count" do |r|
        r.count
      end
      column "value" do |r|
        r.first
      end
    end
  end
end

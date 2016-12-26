class MigrateAnnotatedType < ActiveRecord::Migration
  def change
    Annotation.all.each do |a|
      if a.annotated_type == 'Media' and a.context_type == 'Project'
        pm = ProjectMedia.where(project_id: a.context_id, media_id: a.annotated_id).last
        unless pm.nil?
          klass = a.annotation_type.camelize.constantize
          obj = klass.find(a.id)
          obj.disable_es_callbacks = true
          obj.annotated = pm
          obj.save!
        end
      end
    end
  end
end

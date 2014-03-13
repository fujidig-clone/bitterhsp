task :compile => ["compiler.js", "t.js"]

task :default => :compile do
  sh "node t.js"
end

file "compiler.js" => FileList["*.ts"] do |t|
  sh "tsc compiler.ts --out #{t.name}"
end

file "t.js" => FileList["*.hx"] do |t|
  sh "haxe -lib nodejs -debug -main T -js #{t.name}"
end

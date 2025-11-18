namespace :debug do
  desc "Debug lead details page structure"
  task :lead_details, [:lofty_lead_id] => :environment do |t, args|
    unless args[:lofty_lead_id]
      puts "❌ Usage: bin/rails debug:lead_details[LOFTY_LEAD_ID]"
      exit 1
    end

    require 'playwright'
    
    storage_state_path = Rails.root.join('tmp/lofty_storage_state.json')
    
    Playwright.create(playwright_cli_executable_path: 'npx playwright') do |playwright|
      browser = playwright.chromium.launch(headless: true)
      context = browser.new_context(storageState: storage_state_path.to_s)
      page = context.new_page

      url = "#{ENV['LOFTY_BASE_URL']}/admin/home/detail?leadId=#{args[:lofty_lead_id]}"
      puts "🔍 Loading: #{url}"
      
      page.goto(url, waitUntil: 'networkidle')
      page.wait_for_timeout(3000)

      puts "\n" + "=" * 80
      puts "PIPELINE & SEGMENT"
      puts "=" * 80
      
      # Try to find pipeline
      pipeline = page.evaluate(<<~JS)
        (() => {
          const pipelineEl = document.querySelector('[class*="pipeline"]');
          return pipelineEl ? pipelineEl.innerText : 'Not found';
        })()
      JS
      puts "Pipeline element: #{pipeline}"
      
      # Look in Details section
      details_text = page.evaluate(<<~JS)
        (() => {
          // Find the Details section
          const headings = Array.from(document.querySelectorAll('*')).filter(el => el.innerText && el.innerText.includes('Details'));
          if (headings.length > 0) {
            const detailsSection = headings[0].closest('[class*="detail"], [class*="section"]');
            return detailsSection ? detailsSection.innerText : '';
          }
          return '';
        })()
      JS
      puts "\nDetails section text:\n#{details_text[0..500]}"

      puts "\n" + "=" * 80
      puts "TASKS"
      puts "=" * 80
      
      # Extract tasks with all available info
      tasks_info = page.evaluate(<<~JS)
        (() => {
          const tasks = [];
          
          // Look for Tasks heading
          const tasksHeading = Array.from(document.querySelectorAll('*')).find(el => 
            el.tagName === 'H2' || el.tagName === 'H3' && el.innerText === 'Tasks'
          );
          
          if (tasksHeading) {
            // Get the parent container
            const container = tasksHeading.closest('[class*="box"], [class*="section"], [class*="card"]');
            
            if (container) {
              // Find all task items
              const taskItems = container.querySelectorAll('[class*="task"]');
              
              taskItems.forEach(taskEl => {
                const taskData = {
                  html: taskEl.innerHTML.substring(0, 500),
                  text: taskEl.innerText,
                  classes: taskEl.className
                };
                
                tasks.push(taskData);
              });
            }
          }
          
          return {
            tasksFound: tasks.length,
            tasks: tasks
          };
        })()
      JS
      
      puts "Tasks found: #{tasks_info['tasksFound']}"
      if tasks_info['tasks']&.any?
        tasks_info['tasks'].each_with_index do |task, idx|
          puts "\n--- Task #{idx + 1} ---"
          puts "Classes: #{task['classes']}"
          puts "Text:\n#{task['text']}"
          puts "HTML (first 500 chars):\n#{task['html']}"
        end
      else
        puts "No tasks found - trying alternative approach..."
        
        # Try to get the entire Tasks section HTML
        tasks_html = page.evaluate(<<~JS)
          (() => {
            const allText = document.body.innerText;
            if (allText.includes('New Lead: Call 1')) {
              const tasksHeading = Array.from(document.querySelectorAll('*')).find(el => 
                el.innerText && el.innerText.trim() === 'Tasks'
              );
              
              if (tasksHeading) {
                const parent = tasksHeading.parentElement;
                return {
                  html: parent.innerHTML.substring(0, 2000),
                  text: parent.innerText
                };
              }
            }
            return null;
          })()
        JS
        
        if tasks_html
          puts "\nTasks section HTML:\n#{tasks_html['html']}"
          puts "\nTasks section text:\n#{tasks_html['text']}"
        end
      end

      puts "\n" + "=" * 80
      puts "FAMILY MEMBERS"
      puts "=" * 80
      
      family_info = page.evaluate(<<~JS)
        (() => {
          const addFamilyBtn = Array.from(document.querySelectorAll('*')).find(el => 
            el.innerText && el.innerText.includes('Add Family Member')
          );
          
          return {
            found: !!addFamilyBtn,
            text: addFamilyBtn ? addFamilyBtn.closest('[class*="section"]')?.innerText : ''
          };
        })()
      JS
      
      puts "Add Family Member button found: #{family_info['found']}"
      puts "Section text:\n#{family_info['text']}" if family_info['text']

      browser.close
    end
  end
end

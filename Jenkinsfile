// Pipeline de integración continua de Pedalea.
// Se ejecuta en Jenkins (agente Windows) cada vez que hay un commit nuevo en master.
pipeline {
  agent any

  environment {
    FLUTTER_HOME = 'C:\\dev\\flutter'
    PATH = "C:\\dev\\flutter\\bin;C:\\dev\\flutter\\bin\\cache\\dart-sdk\\bin;${env.LOCALAPPDATA}\\Pub\\Cache\\bin;${env.PATH}"
  }

  options {
    buildDiscarder(logRotator(numToKeepStr: '30'))
    timeout(time: 30, unit: 'MINUTES')
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Dependencias') {
      steps { bat 'flutter pub get' }
    }

    stage('Analisis estatico') {
      steps { bat 'flutter analyze --no-fatal-infos --no-fatal-warnings' }
    }

    stage('Pruebas unitarias y de widget') {
      steps {
        bat 'if not exist build mkdir build'
        bat 'flutter test --coverage --machine > build\\test-results.json'
      }
      post {
        always {
          bat 'dart pub global activate junitreport'
          bat 'dart pub global run junitreport:tojunit --input build\\test-results.json --output build\\junit.xml'
          junit testResults: 'build/junit.xml', allowEmptyResults: false
        }
      }
    }

    stage('Cobertura (KPI-7)') {
      steps {
        powershell '''
          $lcov = Get-Content coverage\\lcov.info
          $files = @(); $cur = $null
          foreach ($l in $lcov) {
            if ($l -like 'SF:*') { $cur = [pscustomobject]@{ f = $l.Substring(3); lf = 0; lh = 0 } }
            elseif ($l -like 'LF:*') { $cur.lf = [int]$l.Substring(3) }
            elseif ($l -like 'LH:*') { $cur.lh = [int]$l.Substring(3) }
            elseif ($l -eq 'end_of_record') { $files += $cur }
          }
          $tot = ($files | Measure-Object lf -Sum).Sum; $hit = ($files | Measure-Object lh -Sum).Sum
          $crit = $files | Where-Object { $_.f -match 'fall_detection|proximity_alert|karma_service|co2_service|ride_stats_service|cache_service' }
          $ctot = ($crit | Measure-Object lf -Sum).Sum; $chit = ($crit | Measure-Object lh -Sum).Sum
          $out = @()
          $out += 'Cobertura global: {0:N1}% ({1}/{2} lineas)' -f (100 * $hit / [Math]::Max($tot,1)), $hit, $tot
          $out += 'Cobertura modulos criticos: {0:N1}% ({1}/{2} lineas)' -f (100 * $chit / [Math]::Max($ctot,1)), $chit, $ctot
          foreach ($c in $crit) { $out += ('  {0}: {1:N1}%' -f (($c.f -replace '\\\\', '/') -replace '.*lib/', 'lib/'), (100 * $c.lh / [Math]::Max($c.lf,1))) }
          $out | Out-File -FilePath build\\coverage-summary.txt -Encoding utf8
          $out | ForEach-Object { Write-Output $_ }
        '''
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'build/junit.xml, build/coverage-summary.txt, coverage/lcov.info', allowEmptyArchive: true
    }
  }
}

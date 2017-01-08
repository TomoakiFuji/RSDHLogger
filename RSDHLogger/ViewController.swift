//
//  ViewController.swift
//  RSDHLogger
//
//  Created by 藤 智亮 on 2016/11/02.
//  Copyright © 2016年 Tomoaki Fuji. All rights reserved.
//

import UIKit
import CoreLocation
import CoreBluetooth
import AVFoundation
import AudioToolbox
import CoreMotion

// 音の監視
private func AQInputCallback(
                _ inUserData: UnsafeMutableRawPointer?,
                inAQ: AudioQueueRef,
                inBuffer: AudioQueueBufferRef,
                inStartTime: UnsafePointer<AudioTimeStamp>,
                inNumberPacketDescriptions: UInt32,
                inPacketDescs: UnsafePointer<AudioStreamPacketDescription>?) {
    // Do nothing, because not recoding.
}

class ViewController: UIViewController, UITextFieldDelegate, CLLocationManagerDelegate, URLSessionDelegate, CBCentralManagerDelegate {
    
    // ファイル更新の時間間隔[s]
    let INTERVAL_FILE = 600.0
    // 加速度計測のサンプリング間隔[s]
    let SAMPLING_INTERVAL_ACC = 0.02
    // マイクレベル監視のサンプリング間隔[s]
    let SAMPLING_INTERVAL_SB = 0.1
    // 歩数保存の時間間隔[s]
    let STEPSAVEINTERVAL = 1

    @IBOutlet var scrollView: UIScrollView!

    @IBOutlet var singleTapGesture: UITapGestureRecognizer!

    // 表示用ラベル
    @IBOutlet var status: UILabel!
    
    @IBOutlet var label1a: UILabel!
    @IBOutlet var label1b: UILabel!
    @IBOutlet var label1c: UILabel!
    
    @IBOutlet var label2a: UILabel!
    @IBOutlet var label2b: UILabel!
    @IBOutlet var label2c: UILabel!
    
    @IBOutlet var label3a: UILabel!
    @IBOutlet var label3b: UILabel!
    @IBOutlet var label3c: UILabel!
    
    @IBOutlet var label4a: UILabel!
    @IBOutlet var label4b: UILabel!
    @IBOutlet var label4c: UILabel!
    
    @IBOutlet var accX: UILabel!
    @IBOutlet var accY: UILabel!
    @IBOutlet var accZ: UILabel!

    @IBOutlet var stepLabel: UILabel!
    @IBOutlet var upErrLabel: UILabel!
    
    @IBOutlet var volumeLabel: UILabel!
    @IBOutlet var loudLabel: UILabel!
    @IBOutlet var thresholdText: UITextField!

    // 被験者番号入力用テキストフィールド
    @IBOutlet var subjectNo: UITextField!

    @IBOutlet var startRecordingButton: UIButton!
    @IBOutlet var stopRecordingButton: UIButton!
    
    // 音声録音on/offスイッチ
    @IBOutlet var recVoice: UISwitch!

    // マイク位置 上/下 設定ボタン
    @IBOutlet var micPosition: UISegmentedControl!
    
    // bluetoothセントラルマネージャを作成する
    var centralManager: CBCentralManager!
    
    // ロケーションマネージャ
    var locationManager = CLLocationManager()
    
    var beaconRegion: CLBeaconRegion!

    // 会話
    let fileManagerAudio = FileManager()
    var audioRecorder: AVAudioRecorder?
    var fileNameVoice: String = ""
    var fileNameVoiceFull: String = ""

    // 音圧レベル
    var fileNameSP: String = ""
    var fileNameSPFull: String = ""
    var dispSPTimeInterval = 0.0
    
    // 音圧レベル監視用
    var queue: AudioQueueRef!
    
    // 加速度
    var motion: CMMotionManager!
    var fileNameAcc: String = ""
    var fileNameAccFull: String = ""
    var dispAccTimeInterval = 0.0

    // 記録フラグ
    var isRecording: Bool = false

    // 同時刻のデータごとに同じindex番号を付与
    var index: Int = 0
    
    // ファイル名に付加する番号
    var fileIndex: Int = 0
    
    // dateの書式
    var dateFormatter: DateFormatter!
    
    // ログファイル用ファイルハンドル
    var fileHandleLoc: FileHandle?
    var fileHandleAcc: FileHandle?
    var fileHandleSP: FileHandle?
    var fileHandleStep: FileHandle?
    
    // ファイル名（位置データ保存用）
    var fileNameLoc: String = ""
    var fileNameLocFull: String = ""
    
    // タイマー
    var timerFile: Timer!
    var timerAcc: Timer!
    var timerSP: Timer!

    // 音感知のしきい値
    var thresholdVolume: Float32 = -10.0
    
    // 歩数取得関連
    var stepEnableFlag: Bool = true
    var stepFileHandleFlag: Bool = true
    var pedometer: CMPedometer!
    var startDate: Date!
    var fileNameStep: String = ""
    var fileNameStepFull: String = ""

    // upload エラー数
    var uploadError: Int32 = 0

    var activityIndicator = UIActivityIndicatorView()

    @IBAction func thresholdChange(_ sender: Any) {
        if Int(thresholdText.text!) == nil {
            thresholdVolume = -10
            thresholdText.text = "-10"
        }
        thresholdVolume = Float32(thresholdText.text!)!
    }

    // アラート表示
    func dispAlert() {
        let alert = UIAlertController(title: "ログ記録開始できません",
                                      message: "被験者番号を入力（半角数字）\nしてください",
                                      preferredStyle: UIAlertControllerStyle.alert)
        alert.addAction(
            UIAlertAction(title: "OK",
                          style: UIAlertActionStyle.default,
                          handler: nil ))
        present(alert, animated: true, completion: nil )
    }
    
    // アラート表示
    func dispAlert2() {
        let alert = UIAlertController(title: "ログ記録開始できません",
                                      message: "マイク接続位置を設定してください",
                                      preferredStyle: UIAlertControllerStyle.alert)
        alert.addAction(
            UIAlertAction(title: "OK",
                          style: UIAlertActionStyle.default,
                          handler: nil ))
        present(alert, animated: true, completion: nil )
    }

    // ファイル名をセットしてファイルハンドルを作成
    func makeFileHandle(fileIndexLocal: Int) {
        // create file prefix
        let documentDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let currentFilePrefix = dateFormatter.string(from: Date())

        let base = subjectNo.text! + "_" + currentFilePrefix + "_" + String(format: "%03d", fileIndexLocal)
        
        fileNameLoc =  base + ".loc"
        fileNameLocFull = documentDirectory + "/" + fileNameLoc
        
        fileNameAcc =  base + ".acc"
        fileNameAccFull = documentDirectory + "/" + fileNameAcc

        if recVoice.isOn == true {
            fileNameVoice =  base + ".caf"
            fileNameVoiceFull = documentDirectory + "/" + fileNameVoice
        }
        
        fileNameSP =  base + ".mic"
        fileNameSPFull = documentDirectory + "/" + fileNameSP
        
        if stepEnableFlag && stepFileHandleFlag {
            fileNameStep = subjectNo.text! + "_" + currentFilePrefix + ".stp"
            fileNameStepFull = documentDirectory + "/" + fileNameStep
        }

        // ファイルハンドルを作成

        // 位置情報記録用
        let text = "index,date,epoch_time,major,minor,accuracy,rssi,proximity\n"
        do {
            try text.write(toFile: fileNameLocFull, atomically: true, encoding: String.Encoding.utf8)
        } catch _ {
        }
        fileHandleLoc = FileHandle(forWritingAtPath: fileNameLocFull)
        fileHandleLoc?.seekToEndOfFile()
        
        // 加速度記録用
        let text2 = "date,epoch_time,acc_x,acc_y,acc_z\n"
        do {
            try text2.write(toFile: fileNameAccFull, atomically: true, encoding: String.Encoding.utf8)
        } catch _ {
        }
        fileHandleAcc = FileHandle(forWritingAtPath: fileNameAccFull)
        fileHandleAcc?.seekToEndOfFile()
        
        // 音圧レベル記録用
        let text3 = "date,epoch_time,PeakPower\n"
        do {
            try text3.write(toFile: fileNameSPFull, atomically: true, encoding: String.Encoding.utf8)
        } catch _ {
        }
        fileHandleSP = FileHandle(forWritingAtPath: fileNameSPFull)
        fileHandleSP?.seekToEndOfFile()
        
        // 歩数記録用
        if stepEnableFlag && stepFileHandleFlag {
            let text4 = "date,steps\n"
            do {
                try text4.write(toFile: fileNameStepFull, atomically: true, encoding: String.Encoding.utf8)
            } catch _ {
            }
            fileHandleStep = FileHandle(forWritingAtPath: fileNameStepFull)
            fileHandleStep?.seekToEndOfFile()
            stepFileHandleFlag = false
        }
    }

    // 加速度取得
    func detectAcc() {
        let data = motion.accelerometerData
        
        var accDataX = data!.acceleration.x
        var accDataY = data!.acceleration.y
        let accDataZ = data!.acceleration.z

        // マイク接続位置が下の場合
        if micPosition.selectedSegmentIndex == 1 {
            accDataX *= -1
            accDataY *= -1
        }

        if isRecording == true {
            let date = Date()
            let dateString = dateFormatter.string(from: date)
            let epochTime = date.timeIntervalSince1970
        
            if let handle = fileHandleAcc {
                let text = NSString(format: "%@,%10.5f,%f,%f,%f\n",
                                                dateString,
                                                epochTime,
                                                accDataX,
                                                accDataY,
                                                accDataZ
                )
                if let d = text.data(using: String.Encoding.utf8.rawValue) {
                    handle.write(d)
                }
            }
        }

        dispAccTimeInterval = dispAccTimeInterval + SAMPLING_INTERVAL_ACC
        if dispAccTimeInterval >= 0.2 {
            accX.text = String(format: "%.2f", data!.acceleration.x)
            accY.text = String(format: "%.2f", data!.acceleration.y)
            accZ.text = String(format: "%.2f", data!.acceleration.z)
            dispAccTimeInterval = 0.0
        }
    }

    // 加速度取得開始
    func startAcc() {
        motion = CMMotionManager()
        if motion.isAccelerometerAvailable == true {
            motion.startAccelerometerUpdates()
            timerAcc = Timer.scheduledTimer(timeInterval: SAMPLING_INTERVAL_ACC, target: self, selector: #selector(ViewController.detectAcc), userInfo: nil, repeats: true)
        }
        dispAccTimeInterval = 0.0
    }

    // ファイルをサーバーにアップロード
    func uploadFile(fileNameLocal: String, fileNameFullLocal: String) {
        // ファイルからデータをバイナリで読み込む
        let fileData = NSData(contentsOfFile: fileNameFullLocal)
        
        let myUrl = URL(string: "http://imech.id.design.kyushu-u.ac.jp/~rsdh/upload.php")
        let myReq = NSMutableURLRequest(url: myUrl!)
        myReq.httpMethod = "POST"
        
        // データを作成
        let boundary = "boundary-code"
        let parameter = "file"
        let contentType = "text/plain"
        
        let body = NSMutableData()
        
        body.append("--\(boundary)\r\n".data(using: String.Encoding.utf8)!)
        
        body.append("Content-Disposition: form-data; name=\"\(parameter)\"; filename=\"\(fileNameLocal)\"\r\n".data(using: String.Encoding.utf8)!)
        body.append("Content-Type: \(contentType)\r\n".data(using: String.Encoding.utf8)!)
        body.append("\r\n".data(using: String.Encoding.utf8)!)
        
        let fileBody = NSMutableData(data: fileData! as Data)
        body.append(fileBody as Data)
        body.append("\r\n".data(using: String.Encoding.utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: String.Encoding.utf8)!)
        
        // ヘッダ部を作成
        myReq.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        myReq.setValue("\(body.length)", forHTTPHeaderField: "Content-Length")
        myReq.httpBody = body as Data
        
        let task = URLSession.shared.dataTask(with: myReq as URLRequest, completionHandler: {
            ( data, res, err ) in
            if data != nil {
                // msgにはサーバーからのメッセージが入る
                let msg = NSString(data: data!, encoding: String.Encoding.utf8.rawValue)
                DispatchQueue.main.async {
                    if msg == "uploaded" {
                        // uploadされたらローカルファイル削除
                        try! FileManager.default.removeItem(atPath: "\(fileNameFullLocal)")
                    } else {
                        self.uploadError = self.uploadError + 1
                        self.upErrLabel.text = "\(self.uploadError)"
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.uploadError = self.uploadError + 1
                    self.upErrLabel.text = "\(self.uploadError)"
                }
            }
        })
        task.resume()
    }

    // ファイルハンドルをクローズしてファイルアップロード
    func fileHandleCloseAndUploadFile() {
        // 位置情報
        fileHandleLoc?.closeFile()
        fileHandleLoc = nil
        uploadFile(fileNameLocal: fileNameLoc,fileNameFullLocal: fileNameLocFull)

        if recVoice.isOn == true {
            // 音声
            uploadFile(fileNameLocal: fileNameVoice,fileNameFullLocal: fileNameVoiceFull)
        }
        
        // 加速度
        fileHandleAcc?.closeFile()
        fileHandleAcc = nil
        uploadFile(fileNameLocal: fileNameAcc, fileNameFullLocal: fileNameAccFull)

        // 音圧レベル
        fileHandleSP?.closeFile()
        fileHandleSP = nil
        uploadFile(fileNameLocal: fileNameSP, fileNameFullLocal: fileNameSPFull)
    }
    
    // 新しいファイルに
    func nextFile() {
        // 書き込み停止
        isRecording = false

        if recVoice.isOn == true {
            // 録音停止
            audioRecorder?.stop()
        }

        // ファイルハンドルをクローズしてファイルアップロード
        fileHandleCloseAndUploadFile()
        
        fileIndex = fileIndex + 1
        makeFileHandle(fileIndexLocal: fileIndex)
        
        if recVoice.isOn == true {
            // 録音開始
            startVoiceRec()
        }
        
        // 書き込み開始
        isRecording = true
    }

    // 音圧レベル取得
    func detectSB()
    {
        // Get level
        var levelMeter = AudioQueueLevelMeterState()
        var propertySize = UInt32(MemoryLayout<AudioQueueLevelMeterState>.size)
        
        AudioQueueGetProperty(
            self.queue,
            kAudioQueueProperty_CurrentLevelMeterDB,
            &levelMeter,
            &propertySize)

        if isRecording == true {
            let date = Date()
            let dateString = dateFormatter.string(from: date)
            let epochTime = date.timeIntervalSince1970
        
            if let handle = fileHandleSP {
                let text = NSString(format: "%@,%10.5f,%f\n",
                                        dateString,
                                        epochTime,
                                        levelMeter.mPeakPower
                )
                if let d = text.data(using: String.Encoding.utf8.rawValue) {
                    handle.write(d)
                }
            }
        }

        dispSPTimeInterval = dispSPTimeInterval + SAMPLING_INTERVAL_SB
        if dispSPTimeInterval >= 0.2 {
            // Show the audio channel's peak power
            // 無音-120 to 最大0 [dB]
            volumeLabel.text = String(format: "%.2f", levelMeter.mPeakPower)
            dispSPTimeInterval = 0.0
        }
            
        // Show "LOUD!!" if mPeakPower is larger than -1.0
        if levelMeter.mPeakPower >= thresholdVolume {
            loudLabel.isHidden = false
        } else {
            loudLabel.isHidden = true
        }
    }
    
    // 音の監視開始
    func startSB() {
        // 音声記録するデータフォーマットを決める
        var dataFormatAudio = AudioStreamBasicDescription(
            mSampleRate: 44100.0,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: AudioFormatFlags(kLinearPCMFormatFlagIsBigEndian |
                kLinearPCMFormatFlagIsSignedInteger |
                kLinearPCMFormatFlagIsPacked),
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0)

        var audioQueue: AudioQueueRef? = nil
        var error = noErr
        error = AudioQueueNewInput(
            &dataFormatAudio,
            AQInputCallback,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            .none,
            .none,
            0,
            &audioQueue)
        if error == noErr {
            self.queue = audioQueue
        }
        AudioQueueStart(self.queue, nil)
        
        // マイクのレベル取得のためにレベルメータを有効化
        var enabledLevelMeter: UInt32 = 1
        AudioQueueSetProperty(self.queue,
                              kAudioQueueProperty_EnableLevelMetering,
                              &enabledLevelMeter,
                              UInt32(MemoryLayout<UInt32>.size))
        
        timerSP = Timer.scheduledTimer(timeInterval: SAMPLING_INTERVAL_SB, target: self, selector: #selector(ViewController.detectSB), userInfo: nil, repeats: true)
        dispSPTimeInterval = 0.0
    }
    
    // 録音するファイルのパスを取得(録音時、再生時に参照)
    func documentFilePath()-> URL {
        let urls = fileManagerAudio.urls(for: .documentDirectory, in: .userDomainMask) as [URL]
        let dirURL = urls[0]
        
        return dirURL.appendingPathComponent(fileNameVoice)
    }
    
    // 録音開始
    func startVoiceRec() {
        // 録音設定
        let recordSetting : [String : AnyObject] = [
            //            AVFormatIDKey : UInt(kAudioFormatAppleLossless) as AnyObject,   // iOS9から必要, 音質良いが容量ほぼ倍
            AVFormatIDKey : UInt(kAudioFormatAppleIMA4) as AnyObject,   // iOS9から必要
            AVEncoderAudioQualityKey : AVAudioQuality.min.rawValue as AnyObject,
            AVEncoderBitRateKey : 16 as AnyObject,  // 以下3行の値は要検討、上2行も？
            AVNumberOfChannelsKey: 1 as AnyObject,
            AVSampleRateKey: 8000.0 as AnyObject
        ]

        // AVAudioRecorderオブジェクト生成
        do {
            try audioRecorder = AVAudioRecorder(url: self.documentFilePath(), settings: recordSetting)
        } catch {
            print("audioRecorderの初期設定エラー")
        }

        audioRecorder?.record()
    }
    
    // 歩数データを保存
    func saveSteps() {
        if stepEnableFlag {
            var stepString:[String] = [""]
            var stepDate:[String] = [""]

            // この日から [s]
//            let fromDate = Date(timeIntervalSinceNow: -60 * 90)
            let fromDate = startDate
            // この日まで
            let toDate = Date()
            
            var fromDateTmp: Date!
            var toDateTmp: Date!
            
            var i: Int = 0
            var j: Int = 0

            fromDateTmp = fromDate
            toDateTmp = fromDateTmp + TimeInterval(STEPSAVEINTERVAL)
            while toDateTmp <= toDate {
//                print(dateFormatter.string(from: fromDateTmp))
                pedometer.queryPedometerData(from: fromDateTmp, to: toDateTmp, withHandler: { data, error in
                    if error != nil {
                        print("歩行データ取得エラー")
                    } else {
                        let steps = data?.numberOfSteps
                        if i == 0 {
                            stepString[i] = (steps?.stringValue)!
                            stepDate[i] = self.dateFormatter.string(from: toDateTmp)
                        } else {
                            stepString.append((steps?.stringValue)!)
                            stepDate.append(self.dateFormatter.string(from: toDateTmp))
                        }
//                        print(stepString[i])
                        i += 1
                    }
                })
                
                // 処理待ち
                j += 1
                while j != i {
                }
                
                fromDateTmp = toDateTmp
                toDateTmp = fromDateTmp + TimeInterval(STEPSAVEINTERVAL)
            }
            
            for j in 0..<i {
                if let handle = fileHandleStep {
                    let text = NSString(format: "%@,%@\n", stepDate[j], stepString[j])
                    if let d = text.data(using: String.Encoding.utf8.rawValue) {
                        handle.write(d)
                    }
                }
            }
        
            fileHandleStep?.closeFile()
            fileHandleStep = nil
            uploadFile(fileNameLocal: fileNameStep, fileNameFullLocal: fileNameStepFull)
        }
    }
    
    // ログ記録開始
    @IBAction func startRecorging(_ sender: AnyObject) {
        if subjectNo.text == "" {
            dispAlert()
            return
        }
        
        if micPosition.selectedSegmentIndex < 0 {
            dispAlert2()
            return
        }

        startRecordingButton.isHidden = true
        stopRecordingButton.isHidden = false
        
        // ファイルアップロードのエラー数リセット
        uploadError = 0
        upErrLabel.text = "0"

        index = 0
        recVoice.isEnabled = false
        micPosition.isEnabled = false
        subjectNo.isEnabled = false

        fileIndex = 1
        makeFileHandle(fileIndexLocal: fileIndex)

        // 歩数取得開始
        if stepEnableFlag {
            stepFileHandleFlag = true
            // 開始日時を保存
            startDate = Date()
            getSteps()
        }
        
        // ファイル更新タイミングtimer起動
        timerFile = Timer.scheduledTimer(timeInterval: INTERVAL_FILE, target: self, selector: #selector(ViewController.nextFile), userInfo: nil, repeats: true)
        
        // 記録開始
        isRecording = true

        // 録音開始
        if recVoice.isOn == true {
            startVoiceRec()
        }
    }
    
    // インジケーターを表示
    func dispIndicator() {
        activityIndicator.startAnimating()
    }
    
    // インジケーターを消す
    func hideIndicator() {
        activityIndicator.stopAnimating()
    }
    
    // ログ記録終了
    @IBAction func stopRecording(_ sender: AnyObject) {

        // インジケーターを表示
//        Thread.detachNewThreadSelector(#selector(ViewController.dispIndicator), toTarget: self, with: nil)
        performSelector(inBackground: #selector(ViewController.dispIndicator), with: nil)

        // キータッチを無効に
        UIApplication.shared.beginIgnoringInteractionEvents()

        stopRecordingButton.isHidden = true

        isRecording = false
        
        // タイマー停止
        timerFile?.invalidate()

        if recVoice.isOn == true {
            // 録音停止
            audioRecorder?.stop()
        }
        
        // 歩数データを保存
        if stepEnableFlag {
            saveSteps()
        }
        
        // ファイルハンドルをクローズしてファイルアップロード
        fileHandleCloseAndUploadFile()

        recVoice.isEnabled = true
        micPosition.isEnabled = true
        subjectNo.isEnabled = true

        // インジケーターを消す
        hideIndicator()

        // キータッチを有効に
        UIApplication.shared.endIgnoringInteractionEvents()

        // 0.02s遅延
        let dispatchTime: DispatchTime = DispatchTime.now() + Double(Int64(0.02 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
        DispatchQueue.main.asyncAfter(deadline: dispatchTime, execute: {
            self.startRecordingButton.isHidden = false
        })
    
    }

    // データ書き込み
    func writeBeaconData( _ beacons: [CLBeacon], epochTimeLocal: TimeInterval, dateStringLocal: String ) {

        var proximity: String = ""
        
        index += 1
            
        for i in 0 ..< beacons.count {
            if (beacons[i].proximity == CLProximity.unknown) {
                proximity = "<Unknown>"
            } else if (beacons[i].proximity == CLProximity.immediate) {
                proximity = "Immediate"
            } else if (beacons[i].proximity == CLProximity.near) {
                proximity = "Near"
            } else if (beacons[i].proximity == CLProximity.far) {
                proximity = "Far"
            }
            
            if let handle = fileHandleLoc {
                let text = NSString(format: "%d,%@,%10.5f,%@,%@,%@,%@,%@\n",
                                    self.index,
                                    dateStringLocal,
                                    epochTimeLocal,
                                    "\(beacons[i].major)",
                                    "\(beacons[i].minor)",
                                    "\(beacons[i].accuracy)",
                                    "\(beacons[i].rssi)",
                                    proximity
                )
                if let d = text.data(using: String.Encoding.utf8.rawValue) {
                    handle.write(d)
                }
            }
        }
    }
    
    // 録音するために必要な初期設定
    func initRec() {
        // オーディオセッションカテゴリを設定
        let session = AVAudioSession.sharedInstance()
        try! session.setCategory(AVAudioSessionCategoryRecord)
        try! session.setActive(true)
    }

    // アプリ終了直前にコール
    func appliTerminate() {
        // 加速度取得停止
        timerAcc?.invalidate()
        motion.stopAccelerometerUpdates()

        // 歩数取得停止
        pedometer.stopUpdates()

        // 音圧レベル取得停止
        timerSP?.invalidate()
        AudioQueueFlush(self.queue)
        AudioQueueStop(self.queue, false)
        AudioQueueDispose(self.queue, true)
        
        // 音声録音可否ボタンの設置値記憶
        UserDefaults.standard.set(recVoice.isOn, forKey: "recVoice")
        
        // マイク接続位置の設置値記憶
        if micPosition.selectedSegmentIndex >= 0 {
            UserDefaults.standard.set(micPosition.selectedSegmentIndex, forKey: "micPosition")
        }
    }

    // 歩数取得
    func getSteps() {
        self.stepLabel.text = "0"
        // 歩数計を生成
        pedometer = CMPedometer()
        
        // CMPedometerが利用できるか確認
        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: Date(), withHandler: {
                [unowned self] data, error in
                DispatchQueue.main.async(execute: {
                    print("update steps")
                    if error != nil {
                        // エラー
                        self.stepLabel.text = "エラー : \(error)"
                    } else {
                        let steps: NSNumber = data!.numberOfSteps
                        self.stepLabel.text = steps.stringValue
                        print(steps.stringValue)
                    }
                })
            })
            stepEnableFlag = true
        } else {
            self.stepLabel.text = "検知不能"
            stepEnableFlag = false
        }

    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let notificationCenter = NotificationCenter.default
        // アプリ終了時直前にコールする関数設定
        notificationCenter.addObserver(self, selector: #selector(ViewController.appliTerminate), name: NSNotification.Name.UIApplicationWillTerminate, object: nil)
        
        // 設定値呼び出し（保存している場合）
        if( UserDefaults.standard.object(forKey: "subjectNo") != nil ) {
            subjectNo.text = UserDefaults.standard.object(forKey: "subjectNo") as! String?
        }
        if( UserDefaults.standard.object(forKey: "thresholdText") != nil ) {
            thresholdText.text = UserDefaults.standard.object(forKey: "thresholdText") as! String?
            thresholdVolume = Float32(thresholdText.text!)!
        }
        if( UserDefaults.standard.object(forKey: "recVoice") != nil ) {
            recVoice.isOn = UserDefaults.standard.object(forKey: "recVoice") as! Bool
        }
        if( UserDefaults.standard.object(forKey: "micPosition") != nil ) {
            micPosition.selectedSegmentIndex = UserDefaults.standard.object(forKey: "micPosition") as! Int
        }

        // リターンキー押下でキーボードを閉じる
        self.subjectNo.delegate = self
        self.thresholdText.delegate = self

        // インジケーター初期設定
        activityIndicator.frame = self.view.frame
        activityIndicator.backgroundColor = UIColor(white: 1.0, alpha: 0.5)
        activityIndicator.center = self.view.center
        activityIndicator.hidesWhenStopped = true
        activityIndicator.activityIndicatorViewStyle = UIActivityIndicatorViewStyle.gray
        view.addSubview(activityIndicator)
        
        // create date formatter
        dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        
        // bluetoothセントラルマネージャの作成
        centralManager = CBCentralManager(delegate: self, queue: nil)
        
        // デリゲートを自身に設定
        locationManager.delegate = self
        
        // バックグラウンドでの位置情報取得を許可
        if #available(iOS 9.0, *) {
            locationManager.allowsBackgroundLocationUpdates = true
        }
        
        // BeaconのUUIDを設定
        let uuid:UUID? = UUID(uuidString: "00000000-A8C8-1001-B000-001C4DFC3B8D")
        // Beaconの識別情報の設定
        self.beaconRegion = CLBeaconRegion(proximityUUID: uuid!, identifier: "Identifier")

        // 歩数取得
        getSteps()
        
        // 録音するために必要な初期設定
        initRec()

        // 加速度取得開始
        startAcc()

        // 音の監視開始
        startSB()
    }

    // 編集対象テキストフィールドを判定
    var txtActiveField = UITextField()
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        txtActiveField = textField
        return true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        NotificationCenter.default.addObserver(self,    selector: #selector(keyboardWillBeShown),
                                                        name: NSNotification.Name.UIKeyboardWillShow,
                                                        object: nil)
        NotificationCenter.default.addObserver(self,    selector: #selector(keyboardWillBeHidden),
                                                        name: NSNotification.Name.UIKeyboardWillHide,
                                                        object: nil)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIKeyboardWillShow,
                                                        object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIKeyboardWillHide,
                                                        object: nil)
    }

    func keyboardWillBeShown(notification: NSNotification) {
        if let userInfo = notification.userInfo {
            if let keyboardFrame = (userInfo[UIKeyboardFrameEndUserInfoKey] as AnyObject).cgRectValue, let animationDuration = (userInfo[UIKeyboardAnimationDurationUserInfoKey] as AnyObject).doubleValue {
                restoreScrollViewSize()
                
                let convertedKeyboardFrame = scrollView.convert(keyboardFrame, from: nil)
                let offsetY: CGFloat = txtActiveField.frame.maxY - convertedKeyboardFrame.minY + 8.0
                if offsetY < 0 { return }
                updateScrollViewSize(moveSize: offsetY, duration: animationDuration)
            }
        }
    }
    
    func keyboardWillBeHidden(notification: NSNotification) {
        restoreScrollViewSize()
    }
    
    func updateScrollViewSize(moveSize: CGFloat, duration: TimeInterval) {
        UIView.beginAnimations("ResizeForKeyboard", context: nil)
        UIView.setAnimationDuration(duration)
        
        let contentInsets = UIEdgeInsetsMake(0, 0, moveSize, 0)
        scrollView.contentInset = contentInsets
        scrollView.scrollIndicatorInsets = contentInsets
        scrollView.contentOffset = CGPoint(x: 0, y: moveSize)
        
        UIView.commitAnimations()
    }
    
    func restoreScrollViewSize() {
        scrollView.contentInset = UIEdgeInsets.zero
        scrollView.scrollIndicatorInsets = UIEdgeInsets.zero
    }

    func reset() {
        label1a.text = ""
        label1b.text = ""
        label1c.text = ""
        label2a.text = ""
        label2b.text = ""
        label2c.text = ""
        label3a.text = ""
        label3b.text = ""
        label3c.text = ""
        label4a.text = ""
        label4b.text = ""
        label4c.text = ""
    }

    // 位置情報認証のステータスが変更された時に呼ばれる
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        // 位置情報認証のステータス
        var statusStr = ""
        
        print("位置情報認証のステータスが変更されました（起動時は必ず呼ばれる）")
        
        // 認証のステータスをチェック
        switch (status) {
        case .notDetermined:
            statusStr = "NotDetermined"
            // 位置情報取得の認証
            locationManager.requestAlwaysAuthorization()
            break
        case .restricted:
            statusStr = "Restricted"
            break
        case .denied:
            statusStr = "Denied"
            self.status.text   = "位置情報の利用が許可されていません"
            break
        case .authorizedAlways:
            // 位置情報の利用が許可されている
            statusStr = "Authorized"
            self.status.text   = "リージョン監視を開始しました"
            // エリアへの出入りを監視する「リージョン監視」開始（観測開始）
            locationManager.startMonitoring(for: self.beaconRegion)
            break
        default:
            break
        }
        
        print("位置情報認証のステータス: \(statusStr)")
        
        if statusStr == "Authorized" {
            print("リージョン監視を開始しました")
        }
    }
    
    //観測の開始に成功すると呼ばれる
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        print("リージョン監視の開始成功")
        //観測開始に成功したら、領域内にいるかどうかの判定をおこなう。→（didDetermineState）へ
        locationManager.requestState(for: self.beaconRegion)
    }
    
    //領域内にいるかどうかを判定する
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for inRegion: CLRegion) {
        switch (state) {
        case .inside: // すでに領域内にいる場合は（didEnterRegion）は呼ばれない
            // エリア内でのビーコン情報を取得する「レージング」開始
            self.locationManager.startRangingBeacons(in: self.beaconRegion)
            status.text = "領域内にいるのでレージング開始しました"
            print("領域内にいるのでレージング開始しました")
            break
        case .outside:
            // 領域外→領域に入った場合はdidEnterRegionが呼ばれる
            break
        case .unknown:
            // 不明→領域に入った場合はdidEnterRegionが呼ばれる
            break
        }
    }
    
    // 領域に入った時
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        // エリア内でのビーコン情報を取得する「レージング」開始
//        self.locationManager.startRangingBeacons(in: self.beaconRegion)
        status.text = "領域に入りました"
        print("領域に入りました")
        //        sendLocalNotificationWithMessage("領域に入りました")
    }
    
    // 領域から出た時
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        // エリア内でのビーコン情報を取得する「レージング」停止
        self.locationManager.stopRangingBeacons(in: self.beaconRegion)
        reset()
        status.text = "領域から出たのでレージング停止しました"
        print("領域から出たのでレージング停止しました")
//        sendLocalNotificationWithMessage("領域から出ました")
    }
    
    // 観測失敗
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("観測失敗（Bluetoothオフ？）")
    }
    
    // 通信失敗
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("通信失敗：\(error)")
    }
    
    // 領域内にいるので測定をする
    func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {

        reset()
        status.text   = "検知ビーコン数: \(beacons.count)"
        
        if beacons.count == 0 {
            return
        }

        let date = Date()
        let dateString = dateFormatter.string(from: date)
        let epochTime = date.timeIntervalSince1970

        //ビーコンの数だけ繰り返し
        for i in 0 ..< beacons.count {
            /*
             beaconから取得できるデータ
             proximityUUID   :   regionの識別子
             major           :   識別子１
             minor           :   識別子２
             proximity       :   相対距離
             accuracy        :   精度
             rssi            :   電波強度
             */
            
            var distance: String = ""
            var accuracy: String = ""

            if (beacons[i].proximity == CLProximity.unknown) {
                distance = "<unknown>"
            } else if (beacons[i].proximity == CLProximity.immediate) {
                distance = "Immediate"
            } else if (beacons[i].proximity == CLProximity.near) {
                distance = "Near"
            } else if (beacons[i].proximity == CLProximity.far) {
                distance = "Far"
            }

            accuracy = String(format: "%.2f", beacons[i].accuracy)
            
            if i == 0 {
                label1a.text = "Major: \(beacons[i].major),  Minor: \(beacons[i].minor)"
                label1b.text = "Proximity: \(distance),  Accuracy: \(accuracy) [m]"
                label1c.text = "RSSI: \(beacons[i].rssi) [dBm]"
            } else if i == 1 {
                label2a.text = "Major: \(beacons[i].major),  Minor: \(beacons[i].minor)"
                label2b.text = "Proximity: \(distance),  Accuracy: \(accuracy) [m]"
                label2c.text = "RSSI: \(beacons[i].rssi) [dBm]"
            } else if i == 2 {
                label3a.text = "Major: \(beacons[i].major),  Minor: \(beacons[i].minor)"
                label3b.text = "Proximity: \(distance),  Accuracy: \(accuracy) [m]"
                label3c.text = "RSSI: \(beacons[i].rssi) [dBm]"
            } else if i == 3 {
                label4a.text = "Major: \(beacons[i].major),  Minor: \(beacons[i].minor)"
                label4b.text = "Proximity: \(distance),  Accuracy: \(accuracy) [m]"
                label4c.text = "RSSI: \(beacons[i].rssi) [dBm]"
            }
//          self.uuid.text     = beacons[i].proximityUUID.uuidString
        }
        if isRecording == true {
            writeBeaconData( beacons, epochTimeLocal: epochTime, dateStringLocal: dateString )
        }
    }

    // 設定値保存
    func saveParameter() {
        UserDefaults.standard.set(subjectNo.text, forKey: "subjectNo")
        UserDefaults.standard.set(thresholdText.text, forKey: "thresholdText")      
    }
    
    // キーボードを閉じる（画面タップで）
//    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
//        saveParameter() // 設定値保存
//        self.view.endEditing(true)
//    }
    @IBAction func tapScreen(_ sender: Any) {
        saveParameter() // 設定値保存
        self.view.endEditing(true)
    }
    
    // キーボードを閉じる（リターンキー押下で）
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        saveParameter() // 設定値保存
        subjectNo.resignFirstResponder()
        thresholdText.resignFirstResponder()

        return true
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // bluetoothセントラルマネージャの状態変化を取得
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
//        print("bluetooth state: \(central.state)")
    }
    
}

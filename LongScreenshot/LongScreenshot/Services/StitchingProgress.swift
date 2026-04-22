import Foundation

/// 拼接处理阶段
enum StitchingPhase: String, CaseIterable {
    case loading = "加载图片"
    case analyzing = "分析重叠区域"
    case processing = "处理图像融合"
    case stitching = "拼接图片"
    case finalizing = "生成最终图片"
    
    var progressWeight: Double {
        switch self {
        case .loading: return 0.15
        case .analyzing: return 0.25
        case .processing: return 0.30
        case .stitching: return 0.25
        case .finalizing: return 0.05
        }
    }
}

/// 拼接进度追踪器
final class StitchingProgress: ObservableObject {
    @Published private(set) var currentProgress: Double = 0.0
    @Published private(set) var currentPhase: StitchingPhase = .loading
    @Published private(set) var isCancelled: Bool = false
    
    private var phaseProgress: [StitchingPhase: Double] = [:]
    private let lock = NSLock()
    
    var progressHandler: ((Double, StitchingPhase) -> Void)?
    
    /// 获取当前进度描述
    var progressDescription: String {
        let percentage = Int(currentProgress * 100)
        return "\(currentPhase.rawValue) \(percentage)%"
    }
    
    /// 开始新任务
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        
        currentProgress = 0.0
        currentPhase = .loading
        isCancelled = false
        phaseProgress.removeAll()
        StitchingPhase.allCases.forEach { phaseProgress[$0] = 0.0 }
    }
    
    /// 取消任务
    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        isCancelled = true
    }
    
    /// 检查是否已取消
    func checkCancellation() throws {
        if isCancelled {
            throw CancellationError()
        }
    }
    
    /// 更新当前阶段
    func updatePhase(_ phase: StitchingPhase) {
        lock.lock()
        defer { lock.unlock() }
        
        currentPhase = phase
        updateTotalProgress()
        
        Task { @MainActor in
            progressHandler?(currentProgress, phase)
        }
    }
    
    /// 更新阶段进度 (0.0 - 1.0)
    func updatePhaseProgress(_ phase: StitchingPhase, progress: Double) {
        lock.lock()
        defer { lock.unlock() }
        
        let clampedProgress = max(0.0, min(1.0, progress))
        phaseProgress[phase] = clampedProgress
        updateTotalProgress()
        
        Task { @MainActor in
            progressHandler?(currentProgress, currentPhase)
        }
    }
    
    /// 计算总进度
    private func updateTotalProgress() {
        var totalProgress: Double = 0.0
        
        for phase in StitchingPhase.allCases {
            let phaseWeight = phase.progressWeight
            let phaseProg = phaseProgress[phase] ?? 0.0
            
            if phase == currentPhase {
                totalProgress += phaseWeight * phaseProg
            } else if phase.rawValue < currentPhase.rawValue {
                totalProgress += phaseWeight
            }
        }
        
        currentProgress = min(1.0, totalProgress)
    }
    
    /// 完成加载，设置进度为100%
    func finishLoading() {
        lock.lock()
        defer { lock.unlock() }
        
        currentProgress = 1.0
        currentPhase = .finalizing
        phaseProgress[.finalizing] = 1.0
        
        Task { @MainActor in
            progressHandler?(currentProgress, currentPhase)
        }
    }
}

/// 可取消的异步任务包装器
struct CancellableTask<T> {
    let task: Task<T, Error>
    let progress: StitchingProgress
    
    func cancel() {
        progress.cancel()
        task.cancel()
    }
    
    var value: T {
        get async throws {
            try await task.value
        }
    }
}
